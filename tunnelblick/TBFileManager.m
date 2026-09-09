//  TBFileManager.m
//
//  Created by Jonathan Bullard on 9/3/26.
//

#import "TBFileManager.h"

#pragma mark - Constants

NSString * const TBFMErrorDomain = @"TBFMErrorDomain";

// Sentinel returned by TBFMPathComponents when "." or ".." was encountered.
// An NSString is used so dictionary-style handling remains type-safe.
#define kTBFMBadComponentMarker @"\x01TBFM_INVALID_COMPONENT\x01"

#pragma mark - Private interfaces

@interface TBFMSnapshotEnumerator ()
{
    @private
    NSMutableArray *_paths;   // private snapshot, retained
    NSUInteger      _index;
}
- (id)initWithPaths:(NSArray *)paths;
@end

@interface TBFMEnumerator ()
{
    @private
    NSMutableArray  *_stack;              // TBFMFrame objects, top = last
    NSRecursiveLock *_lock;               // shared with owning TBFileManager (retained)
    BOOL             _didPushChildFrame;  // YES iff top frame belongs to the
                                          // path most recently returned
}
- (id)initWithDirectory:(NSDictionary *)dir
             pathPrefix:(NSString *)prefix
                   lock:(NSRecursiveLock *)lock;
- (void)_pushFrameForDirectory:(NSDictionary *)dir pathPrefix:(NSString *)prefix;
@end

@interface TBFileManager ()
{
@private
    NSMutableDictionary *_root;      // owns the whole tree
    NSRecursiveLock     *_lock;      // recursive: public APIs call helpers freely
}
- (NSMutableDictionary *)_directoryAtPath:(NSString *)path
                       createIntermediate:(BOOL)create;
- (BOOL)_parentDirectory:(NSMutableDictionary **)parentOut
          finalComponent:(NSString **)nameOut
                 forPath:(NSString *)path;
- (BOOL)_fail:(TBFMErrorCode)code
     outError:(NSError **)outError
      message:(NSString *)message;
- (NSDictionary *)_dictionaryForEntry:(id)entry;
@end

#pragma mark - Helpers

// Normalize: strip leading/trailing slashes, split, drop empty components.
// "." and ".." components are rejected via kTBFMBadComponentMarker, which
// callers must validate with TBFMComponentsAreValid().
static NSArray *TBFMPathComponents(NSString *path) {
    if (!path || [path length] == 0 || [path isEqualToString:@"/"]) {
        return [NSArray array];
    }

    NSString *trimmed = [path stringByTrimmingCharactersInSet:
                         [NSCharacterSet characterSetWithCharactersInString:@"/"]];
    if ([trimmed length] == 0) {
        return [NSArray array];
    }

    NSArray *raw = [trimmed componentsSeparatedByString:@"/"];
    NSMutableArray *components = [NSMutableArray arrayWithCapacity:[raw count]];

    NSEnumerator *e = [raw objectEnumerator];
    NSString *c = nil;
    while ((c = [e nextObject])) {
        if ([c length] > 0) {
            if ([c isEqualToString:@"."] || [c isEqualToString:@".."]) {
                return [NSArray arrayWithObject:kTBFMBadComponentMarker];
            }
            [components addObject:c];
        }
    }

    return components;
}

static BOOL TBFMComponentsAreValid(NSArray *components) {
    return [components count] > 0 &&
           ![components isEqualToArray:[NSArray arrayWithObject:kTBFMBadComponentMarker]];
}

static BOOL TBFMIsDirectoryObject(id obj) {
    return [obj isKindOfClass:[NSMutableDictionary class]];
}

static void TBFMCollectPaths(NSMutableArray *accum,
                             NSDictionary   *dir,
                             NSString       *prefix)
{
    NSEnumerator *keyEnum = [[dir allKeys] objectEnumerator];
    NSString *name = nil;

    while ((name = [keyEnum nextObject])) {
        id child = [dir objectForKey:name];
        NSString *childPath = nil;

        if ([prefix length] > 0) {
            childPath = [prefix stringByAppendingPathComponent:name];
        } else {
            childPath = name;
        }

        [accum addObject:childPath];

        if (TBFMIsDirectoryObject(child)) {
            TBFMCollectPaths(accum, (NSDictionary *)child, childPath);
        }
    }
}

#pragma mark - TBFMSnapshotEnumerator (immutable snapshot)

@implementation TBFMSnapshotEnumerator

- (id)initWithPaths:(NSArray *)paths {
    self = [super init];
    if (self) {
        _paths = [paths mutableCopy];
        _index = 0;
    }
    return self;
}

- (id)nextObject {
    if (_index >= [_paths count]) {
        return nil;
    }
    return [_paths objectAtIndex:_index++];
}

- (void)dealloc {
    [_paths release];
    [super dealloc];
}

@end

#pragma mark - TBFMFrame (private, lazy enumeration)

// One DFS stack frame: a live directory reference (read only under the
// manager's lock) plus a key snapshot taken at push time.
@interface TBFMFrame : NSObject
{
    @public
    NSDictionary *_dir;
    NSArray      *_keys;
    NSString     *_pathPrefix;
    NSUInteger    _keyIndex;
}
@end

@implementation TBFMFrame

- (void)dealloc
{
    [_dir release];
    [_keys release];
    [_pathPrefix release];
    [super dealloc];
}

@end

#pragma mark - TBFMEnumerator (lazy, live tree)

@implementation TBFMEnumerator

- (id)initWithDirectory:(NSDictionary *)dir
             pathPrefix:(NSString *)prefix
                   lock:(NSRecursiveLock *)lock
{
    self = [super init];
    if (self) {
        _stack = [[NSMutableArray alloc] init];
        _lock  = [lock retain];
        _didPushChildFrame = NO;
        [self _pushFrameForDirectory:dir pathPrefix:prefix ?: @""];
    }
    return self;
}

- (void)dealloc {
    [_stack release];
    [_lock release];
    [super dealloc];
}

- (void)_pushFrameForDirectory:(NSDictionary *)dir pathPrefix:(NSString *)prefix {
    TBFMFrame *frame = [[TBFMFrame alloc] init];
    frame->_dir = [dir retain];                 // retain live directory
    frame->_keys = [[dir allKeys] copy];        // already a retained snapshot
    frame->_pathPrefix = [prefix copy];         // retained prefix
    frame->_keyIndex = 0;
    [_stack addObject:frame];                   // _stack retains the frame
    [frame release];                            // balanced with alloc
}
- (id)nextObject {
    [_lock lock];
    @try {
        while ([_stack count] > 0) {
            TBFMFrame *frame = [_stack lastObject];

            if (frame->_keyIndex >= [frame->_keys count]) {
                // Frame exhausted: pop and resume the parent directory.
                [_stack removeLastObject];
                continue;
            }

            NSString *name = [frame->_keys objectAtIndex:frame->_keyIndex];
            frame->_keyIndex++;

            // Entry may have been removed since the key snapshot was taken.
            id child = [frame->_dir objectForKey:name];
            if (!child) {
                continue;
            }

            NSString *path;
            if ([frame->_pathPrefix length] > 0) {
                path = [frame->_pathPrefix stringByAppendingPathComponent:name];
            } else {
                path = name;
            }

            if (TBFMIsDirectoryObject(child)) {
                [self _pushFrameForDirectory:(NSDictionary *)child
                                  pathPrefix:path];
                _didPushChildFrame = YES;   // caller may skipDescendants this
            } else {
                _didPushChildFrame = NO;
            }

            return path;
        }
        return nil;
    }
    @finally {
        [_lock unlock];
    }
}

// Applies to the entry most recently returned by nextObject. No-op if that
// entry was a file, or if nextObject hasn't been called yet.
- (void)skipDescendants {
    [_lock lock];
    @try {
        if (_didPushChildFrame) {
            [_stack removeLastObject];
            _didPushChildFrame = NO;
        }
    }
    @finally {
        [_lock unlock];
    }
}

@end

#pragma mark - TBFileManager

@implementation TBFileManager

+ (TBFileManager *)defaultManager {
    static TBFileManager *sManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sManager = [[TBFileManager alloc] init]; // never released, process lifetime
    });
    return sManager;
}

- (id)init {
    self = [super init];
    if (self) {
        _root = [[NSMutableDictionary alloc] init];
        _lock = [[NSRecursiveLock alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_root release];
    [_lock release];
    [super dealloc];
}

#pragma mark - Internal helpers (caller must hold _lock)

- (BOOL)_fail:(TBFMErrorCode)code
     outError:(NSError **)outError
      message:(NSString *)message
{
    if (outError) {
        *outError = [NSError errorWithDomain:TBFMErrorDomain
                                        code:code
                                    userInfo:@{ NSLocalizedDescriptionKey : message }];
    }
    return NO;
}

// Return directory dictionary at given path (all components are directories).
// If create == YES, intermediate directories are created.
- (NSMutableDictionary *)_directoryAtPath:(NSString *)path
                       createIntermediate:(BOOL)create
{
    NSArray *components = TBFMPathComponents(path);

    if (!TBFMComponentsAreValid(components)) {
        return nil;
    }

    NSMutableDictionary *current = _root;

    NSUInteger count = [components count];
    NSUInteger i;
    for (i = 0; i < count; i++) {
        NSString *comp = [components objectAtIndex:i];
        id child = [current objectForKey:comp];

        if (!child) {
            if (!create) {
                return nil;
            }
            NSMutableDictionary *newDir = [[NSMutableDictionary alloc] init];
            [current setObject:newDir forKey:comp];
            [newDir release];
            child = [current objectForKey:comp];
        }

        if (!TBFMIsDirectoryObject(child)) {
            // Existing non-directory in the path
            return nil;
        }

        current = (NSMutableDictionary *)child;
    }

    return current;
}

// Return parent directory dictionary and final component name for a path.
// parentOut may be nil. Returns YES on success.
- (BOOL)_parentDirectory:(NSMutableDictionary **)parentOut
          finalComponent:(NSString **)nameOut
                 forPath:(NSString *)path
{
    NSArray *components = TBFMPathComponents(path);

    if (!TBFMComponentsAreValid(components)) {
        return NO;
    }

    NSUInteger count = [components count];

    if (count == 0) {
        // Root has no parent
        return NO;
    }

    NSString *name = [components lastObject];
    if (nameOut) {
        *nameOut = name;
    }

    if (count == 1) {
        if (parentOut) {
            *parentOut = _root;
        }
        return YES;
    }

    NSMutableArray *parentComponents = [NSMutableArray arrayWithArray:components];
    [parentComponents removeLastObject];

    NSString *parentPath = [parentComponents componentsJoinedByString:@"/"];
    NSMutableDictionary *parent = [self _directoryAtPath:parentPath
                                      createIntermediate:NO];
    if (!parent) {
        return NO;
    }

    if (parentOut) {
        *parentOut = parent;
    }

    return YES;
}

- (id)_snapshotForEntry:(id)entry {
    if ([entry isKindOfClass:[NSData class]]) {
        return [[entry copy] autorelease];
    }

    if (!TBFMIsDirectoryObject(entry)) {
        return nil;
    }

    NSDictionary * directory = (NSDictionary *)entry;
    NSMutableDictionary * snapshot = [[[NSMutableDictionary alloc] initWithCapacity:[directory count]]
                                      autorelease];

    NSEnumerator *keyEnumerator = [directory keyEnumerator];
    NSString *name = nil;

    while ((name = [keyEnumerator nextObject])) {
        id child = [directory objectForKey:name];
        id childSnapshot = [self _snapshotForEntry:child];

        if (childSnapshot) {
            [snapshot setObject:childSnapshot forKey:name];
        }
    }

    return [[snapshot copy] autorelease];
}
// Caller must hold _lock.
//
// Produces an immutable recursive snapshot. Directory children become
// NSDictionary values; data/file entries are copied as NSData values.
- (NSDictionary *)_dictionaryForEntry:(id)entry {
    if (!TBFMIsDirectoryObject(entry)) {
        return nil;
    }

    NSDictionary *directory = (NSDictionary *)entry;
    NSMutableDictionary *snapshot =
    [[NSMutableDictionary alloc] initWithCapacity:[directory count]];

    NSEnumerator *keyEnumerator = [directory keyEnumerator];
    NSString *name = nil;

    while ((name = [keyEnumerator nextObject])) {
        id child = [directory objectForKey:name];

        if (TBFMIsDirectoryObject(child)) {
            NSDictionary *childDictionary = [self _dictionaryForEntry:child];
            [snapshot setObject:childDictionary forKey:name];
        } else if ([child isKindOfClass:[NSData class]]) {
            NSData *dataSnapshot = [[child copy] autorelease];
            [snapshot setObject:dataSnapshot forKey:name];
        }
    }

    return [snapshot autorelease];
}

#pragma mark - Public API

- (id)dictionaryForEntryAtPath:(NSString *)path {
    if (!path || [path length] == 0 || [path isEqualToString:@"/"]) {
        return nil;
    }

    [_lock lock];
    @try {
        NSMutableDictionary *parent = nil;
        NSString *name = nil;

        if (![self _parentDirectory:&parent
                     finalComponent:&name
                            forPath:path]) {
            return nil;
        }

        id entry = [parent objectForKey:name];
        if (!entry) {
            return nil;
        }

        return [[[self _snapshotForEntry:entry] retain] autorelease];
    }
    @finally {
        [_lock unlock];
    }
}

- (BOOL)entryExistsAtPath:(NSString *)path
              isDirectory:(BOOL *)isDirectory {
    if (isDirectory) {
        *isDirectory = NO;
    }

    if (!path || [path length] == 0 || [path isEqualToString:@"/"]) {
        return NO;
    }

    [_lock lock];
    @try {
        NSMutableDictionary *parent = nil;
        NSString *name = nil;

        if (![self _parentDirectory:&parent
                     finalComponent:&name
                            forPath:path]) {
            return NO;
        }

        id entry = [parent objectForKey:name];
        if (!entry) {
            return NO;
        }

        if (isDirectory) {
            *isDirectory = TBFMIsDirectoryObject(entry);
        }

        return YES;
    }
    @finally {
        [_lock unlock];
    }
}

- (BOOL)createDirectoryAtPath:(NSString *)path error:(NSError **)outError {
    if (!path || [path length] == 0) {
        return [self _fail:TBFMErrorInvalidArgument
                  outError:outError
                   message:@"path must be a non-empty string"];
    }

    [_lock lock];
    @try {
        NSMutableDictionary *dir = [self _directoryAtPath:path
                                       createIntermediate:YES];
        if (!dir) {
            return [self _fail:TBFMErrorTypeMismatch
                      outError:outError
                       message:@"a non-directory entry exists in the path"];
        }
        return YES;
    }
    @finally {
        [_lock unlock];
    }
}

- (BOOL)writeData:(NSData *)data
    toEntryAtPath:(NSString *)path
          replace:(BOOL)replace
            error:(NSError **)outError
{
    if (!data || !path) {
        return [self _fail:TBFMErrorInvalidArgument
                  outError:outError
                   message:@"data and path must not be nil"];
    }

    [_lock lock];
    @try {
        NSMutableDictionary *parent = nil;
        NSString *name = nil;

        if (![self _parentDirectory:&parent finalComponent:&name forPath:path]) {
            return [self _fail:TBFMErrorParentNotDirectory
                      outError:outError
                       message:@"parent directory does not exist"];
        }

        id existing = [parent objectForKey:name];
        if (existing) {
            if (!replace) {
                return [self _fail:TBFMErrorEntryExistsNoReplace
                          outError:outError
                           message:@"entry already exists and replace is NO"];
            }
            if (TBFMIsDirectoryObject(existing)) {
                // Do not allow replacing a directory with a file
                return [self _fail:TBFMErrorTypeMismatch
                          outError:outError
                           message:@"cannot replace a directory with a file"];
            }
        }

        [parent setObject:data forKey:name]; // parent retains data
        return YES;
    }
    @finally {
        [_lock unlock];
    }
}

- (NSData *)readDataAtPath:(NSString *)path {
    if (!path) {
        return nil;
    }

    [_lock lock];
    @try {
        NSMutableDictionary *parent = nil;
        NSString *name = nil;
        if (![self _parentDirectory:&parent finalComponent:&name forPath:path]) {
            return nil;
        }

        id obj = [parent objectForKey:name];
        if (![obj isKindOfClass:[NSData class]]) {
            return nil;
        }

        // Autoreleased retained instance; the autorelease pool keeps it
        // alive even if the tree mutates concurrently.
        return [[obj retain] autorelease];
    }
    @finally {
        [_lock unlock];
    }
}

- (BOOL)movePath:(NSString *)oldPath
              to:(NSString *)newPath
         replace:(BOOL)replace
           error:(NSError **)outError
{
    if (!oldPath || !newPath) {
        return [self _fail:TBFMErrorInvalidArgument
                  outError:outError
                   message:@"oldPath and newPath must not be nil"];
    }

    [_lock lock];
    @try {
        // Source
        NSMutableDictionary *srcParent = nil;
        NSString *srcName = nil;
        if (![self _parentDirectory:&srcParent finalComponent:&srcName forPath:oldPath]) {
            return [self _fail:TBFMErrorNoSuchEntry
                      outError:outError
                       message:@"source path is invalid"];
        }

        id entry = [srcParent objectForKey:srcName];
        if (!entry) {
            return [self _fail:TBFMErrorNoSuchEntry
                      outError:outError
                       message:@"no entry at source path"];
        }

        // Destination
        NSMutableDictionary *dstParent = nil;
        NSString *dstName = nil;
        if (![self _parentDirectory:&dstParent finalComponent:&dstName forPath:newPath]) {
            return [self _fail:TBFMErrorParentNotDirectory
                      outError:outError
                       message:@"destination parent directory does not exist"];
        }

        id dstExisting = [dstParent objectForKey:dstName];
        if (dstExisting) {
            if (!replace) {
                return [self _fail:TBFMErrorEntryExistsNoReplace
                          outError:outError
                           message:@"destination exists and replace is NO"];
            }

            BOOL srcIsDir = TBFMIsDirectoryObject(entry);
            BOOL dstIsDir = TBFMIsDirectoryObject(dstExisting);

            // Disallow replacing directory with file or vice versa
            if (srcIsDir != dstIsDir) {
                return [self _fail:TBFMErrorTypeMismatch
                          outError:outError
                           message:@"source and destination are different types"];
            }
        }

        // Reject moves of a directory into its own subtree (cycle prevention).
        if (TBFMIsDirectoryObject(entry)) {
            NSArray *srcComps = TBFMPathComponents(oldPath);
            NSArray *dstComps = TBFMPathComponents(newPath);

            if (TBFMComponentsAreValid(srcComps) &&
                TBFMComponentsAreValid(dstComps) &&
                [dstComps count] > [srcComps count])
            {
                BOOL isDescendant = YES;
                for (NSUInteger i = 0; i < [srcComps count]; i++) {
                    if (![[srcComps objectAtIndex:i]
                            isEqualToString:[dstComps objectAtIndex:i]]) {
                        isDescendant = NO;
                        break;
                    }
                }
                if (isDescendant) {
                    return [self _fail:TBFMErrorInvalidArgument
                              outError:outError
                               message:@"cannot move a directory into its own subtree"];
                }
            }
        }

        // No-op rename onto itself: avoid mutating enumeration order.
        if (srcParent == dstParent && [srcName isEqualToString:dstName]) {
            return YES;
        }

        // Retain entry during removal from source parent; +1 guarantees
        // survival across both mutations, including same-parent moves.
        [entry retain];
        [srcParent removeObjectForKey:srcName];
        [dstParent setObject:entry forKey:dstName];
        [entry release];

        return YES;
    }
    @finally {
        [_lock unlock];
    }
}

- (BOOL)removeEntryAtPath:(NSString *)path error:(NSError **)outError {
    if (!path) {
        return [self _fail:TBFMErrorInvalidArgument
                  outError:outError
                   message:@"path must not be nil"];
    }

    [_lock lock];
    @try {
        NSMutableDictionary *parent = nil;
        NSString *name = nil;

        if (![self _parentDirectory:&parent finalComponent:&name forPath:path]) {
            return [self _fail:TBFMErrorParentNotDirectory
                      outError:outError
                       message:@"parent directory does not exist"];
        }

        if (![parent objectForKey:name]) {
            return [self _fail:TBFMErrorNoSuchEntry
                      outError:outError
                       message:@"no entry at path"];
        }

        [parent removeObjectForKey:name];
        return YES;
    }
    @finally {
        [_lock unlock];
    }
}

- (TBFMSnapshotEnumerator *)enumeratorAtPath:(NSString *)path {
    [_lock lock];
    @try {
        NSMutableDictionary *dir = nil;

        if (!path || [path length] == 0 || [path isEqualToString:@"/"]) {
            dir = _root;
        } else {
            dir = [self _directoryAtPath:path createIntermediate:NO];
        }

        if (!dir) {
            return nil;
        }

        // Collect paths under the lock, then hand the enumerator an
        // immutable copy so it never touches _root afterwards.
        NSMutableArray *paths = [[NSMutableArray alloc] init];
        TBFMCollectPaths(paths, dir, nil);
        NSArray *snapshot = [[paths copy] autorelease];
        [paths release];

        TBFMSnapshotEnumerator *e =
            [[TBFMSnapshotEnumerator alloc] initWithPaths:snapshot];
        return [e autorelease];
    }
    @finally {
        [_lock unlock];
    }
}

- (TBFMEnumerator *)lazyEnumeratorAtPath:(NSString *)path
{
    // Reject "." / ".." like everywhere else for non-root paths.
    if (path && [path length] > 0 && ![path isEqualToString:@"/"]) {
        NSArray *comps = TBFMPathComponents(path);
        if (!TBFMComponentsAreValid(comps)) {
            return nil;
        }
    }

    [_lock lock];
    @try {
        NSMutableDictionary *dir = nil;

        if (!path || [path length] == 0 || [path isEqualToString:@"/"]) {
            dir = _root;
        } else {
            dir = [self _directoryAtPath:path createIntermediate:NO];
        }

        if (!dir) {
            return nil;
        }

        // Paths returned by the enumerator are relative to 'dir',
        // matching -enumeratorAtPath: semantics.
        return [[[TBFMEnumerator alloc]
                 initWithDirectory:dir
                 pathPrefix:@""
                 lock:_lock] autorelease];
    }
    @finally {
        [_lock unlock];
    }
}
@end

//
//  TBFileManager.h
//
//  Created by Jonathan Bullard on 9/3/26.
//

#import <Foundation/Foundation.h>

@class TBFMSnapshotEnumerator;
@class TBFMEnumerator;

extern NSString * const TBFMErrorDomain;

typedef NS_ENUM(NSInteger, TBFMErrorCode) {
    TBFMErrorInvalidArgument      = 1,  // nil/empty/invalid path or data
    TBFMErrorNoSuchEntry          = 2,  // no entry exists at the given path
    TBFMErrorEntryExistsNoReplace = 3,  // destination exists and replace == NO
    TBFMErrorTypeMismatch         = 4,  // cannot replace dir<->file or vice versa
    TBFMErrorParentNotDirectory   = 5,  // parent path does not exist / is not a directory
};

/// In-memory tree-based file manager (manual reference counting, MRC).
///
/// Paths are "/"-separated strings. Components "." and ".." are rejected
/// in all APIs; leading-dot names like ".foo.bar" are ordinary names.
///
/// Thread safety: all operations take an internal recursive lock and are
/// safe to call concurrently from multiple threads.
@interface TBFileManager : NSObject

+ (TBFileManager *)defaultManager;

/// Creates the directory at `path`, including all missing intermediates.
/// Returns YES if the directory exists (or already existed) afterwards.
- (BOOL)createDirectoryAtPath:(NSString *)path
                        error:(NSError **)outError;

/// Returns YES if either a file or directory entry exists at `path`.
///
/// If `isDirectory` is non-NULL and the method returns YES, stores YES
/// when the entry is a directory and NO when it is a file.
///
/// Returns NO for nil, empty, root, malformed, or nonexistent paths.
/// `*isDirectory` is set to NO whenever `isDirectory` is non-NULL and
/// no entry is found.
- (BOOL)entryExistsAtPath:(NSString *)path
              isDirectory:(BOOL *)isDirectory;

/// Writes `data` at `path`. Fails if an entry already exists and
/// `replace` is NO, or if the existing entry is a directory.
- (BOOL)writeData:(NSData *)data
    toEntryAtPath:(NSString *)path
          replace:(BOOL)replace
            error:(NSError **)outError;

/// Returns the data stored at `path`, autoreleased, or nil if the entry
/// does not exist or is a directory.
- (NSData *)readDataAtPath:(NSString *)path;

/// Returns an immutable, recursive snapshot of the entry at `path`.
///
/// A directory is represented as an NSDictionary: child names map to
/// recursively represented children. A file is represented as NSData.
///
/// Returns nil if `path` is nil, empty, root, malformed, or nonexistent.
- (id)dictionaryForEntryAtPath:(NSString *)path;

/// Moves the entry at `oldPath` to `newPath`. Both files and directories
/// may be moved. Directory/file type must match when replacing. Moving a
/// directory into its own subtree is rejected.
- (BOOL)movePath:(NSString *)oldPath
              to:(NSString *)newPath
         replace:(BOOL)replace
           error:(NSError **)outError;

/// Removes the entry (file or directory) at `path`, including any
/// descendants if it is a directory.
- (BOOL)removeEntryAtPath:(NSString *)path
                    error:(NSError **)outError;

/// Returns a SNAPSHOT enumerator over every path beneath `path`, reflecting
/// the tree state at creation time. The result is immutable and safe to use
/// from any thread.
- (TBFMSnapshotEnumerator *)enumeratorAtPath:(NSString *)path;

/// Returns a LAZY, depth-first enumerator over the LIVE tree: entries
/// created before the walk reaches their directory ARE visited; entries
/// deleted before being reached are skipped. Locks are taken per
/// nextObject call, so it is safe to share across threads, but the walk
/// is NOT a consistent single snapshot.
///
/// Calling -skipDescendants on the result stops descent into the children
/// of the path most recently returned (mirrors NSDirectoryEnumerator).
- (TBFMEnumerator *)lazyEnumeratorAtPath:(NSString *)path;

@end

/// Immutable, pre-materialized enumerator (snapshot semantics).
@interface TBFMSnapshotEnumerator : NSEnumerator
- (id)nextObject;
@end

/// Lazy depth-first enumerator over the live tree.
/// -skipDescendants applies to the entry most recently returned and is a
/// no-op for files.
@interface TBFMEnumerator : NSEnumerator
- (id)nextObject;
- (void)skipDescendants;
@end

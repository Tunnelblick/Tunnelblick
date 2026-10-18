/*
 * Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2018, 2019, 2020, 2021, 2023, 2025, 2026 Jonathan K. Bullard. All rights reserved.
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 */

#import "forcedPreferenceKey.h"

#include <stdio.h>

static int failures = 0;

static void expectTrue(BOOL condition, const char * message) {

    if (  condition  ) {
        printf("OK: %s\n", message);
    } else {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

int main(void) {

    @autoreleasepool {
        NSArray * suffixes = @[@"autoConnect", @"-onSystemStart"];
        expectTrue(forcedPreferenceKeyIsForDisplayName(@"WorkVPNautoConnect", @"WorkVPN", suffixes),
                   "autoConnect key belongs to WorkVPN");
        expectTrue(forcedPreferenceKeyIsForDisplayName(@"WorkVPN-onSystemStart", @"WorkVPN", suffixes),
                   "onSystemStart key belongs to WorkVPN");
        expectTrue( ! forcedPreferenceKeyIsForDisplayName(@"WorkVPNautoConnect", @"Work", suffixes),
                   "a shorter name does not claim the key");
        expectTrue( ! forcedPreferenceKeyIsForDisplayName(@"OtherautoConnect", @"WorkVPN", suffixes),
                   "another configuration's key does not match");
        expectTrue( ! forcedPreferenceKeyIsForDisplayName(@"WorkVPN", @"WorkVPN", suffixes),
                   "the bare display name is not a forced preference key");
    }
    return failures == 0 ? 0 : 1;
}

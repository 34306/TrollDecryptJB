#include <stdio.h>
#import <Foundation/Foundation.h>
#import <rootless.h>
#import "TSUtil.h"

int main(int argc, char *argv[], char *envp[]) {
	@autoreleasepool {
        if (getuid() == 501) {
            if (argc > 1 && strcmp(argv[1], "--child") == 0) {
                exit(1);
            }
            
            spawnRoot(ROOT_PATH_NS(@"/usr/local/bin/TDDaemonKiller"), @[ @"", @"--child" ], nil, nil);
            exit(0);
        }
        killall(@"appstored", NO);
        killall(@"installd", YES);
        killall(@"AppStore", YES);
        exit(0);
	}
}

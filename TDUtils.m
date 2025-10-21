#import "TDUtils.h"
#import "TDDumpDecrypted.h"
#import "LSApplicationProxy+AltList.h"
#import "SSZipArchive/SSZipArchive.h"
#import "appstoretrollerKiller/TSUtil.h"

UIWindow *alertWindow = NULL;
UIWindow *kw = NULL;
UIViewController *root = NULL;
UIAlertController *alertController = NULL;
UIAlertController *doneController = NULL;
UIAlertController *errorController = NULL;

NSArray *appList(void) {
    NSMutableArray *apps = [NSMutableArray array];

    NSArray <LSApplicationProxy *> *installedApplications = [[LSApplicationWorkspace defaultWorkspace] atl_allInstalledApplications];
    [installedApplications enumerateObjectsUsingBlock:^(LSApplicationProxy *proxy, NSUInteger idx, BOOL *stop) {
        if (![proxy atl_isUserApplication]) return;

        NSString *bundleID = [proxy atl_bundleIdentifier];
        NSString *name = [proxy atl_nameToDisplay];
        NSString *version = [proxy atl_shortVersionString];
        NSString *executable = proxy.canonicalExecutablePath;

        if (!bundleID || !name || !version || !executable) return;

        NSDictionary *item = @{
            @"bundleID":bundleID,
            @"name":name,
            @"version":version,
            @"executable":executable
        };

        [apps addObject:item];
    }];

    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    [apps sortUsingDescriptors:@[descriptor]];

    [apps addObject:@{@"bundleID":@"", @"name":@"", @"version":@"", @"executable":@""}];

    return [apps copy];
}

NSUInteger iconFormat(void) {
    return (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 8 : 10;
}

NSArray *sysctl_ps(void) {
    NSMutableArray *array = [[NSMutableArray alloc] init];

    int numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t pids[numberOfProcesses];
    bzero(pids, sizeof(pids));
    proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    for (int i = 0; i < numberOfProcesses; ++i) {
        if (pids[i] == 0) { continue; }
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        bzero(pathBuffer, PROC_PIDPATHINFO_MAXSIZE);
        proc_pidpath(pids[i], pathBuffer, sizeof(pathBuffer));

        if (strlen(pathBuffer) > 0) {
            NSString *processID = [[NSString alloc] initWithFormat:@"%d", pids[i]];
            NSString *processName = [[NSString stringWithUTF8String:pathBuffer] lastPathComponent];
            NSDictionary *dict = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:processID, processName, nil] forKeys:[NSArray arrayWithObjects:@"pid", @"proc_name", nil]];
            
            [array addObject:dict];
        }
    }

    return [array copy];
}

void decryptApp(NSDictionary *app) {
    // Use flexdecrypt method instead of lldb
    decryptAppWithFlexDecrypt(app);
}

void decryptAppWithFlexDecrypt(NSDictionary *app) {
    dispatch_async(dispatch_get_main_queue(), ^{
        alertWindow = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
        alertWindow.rootViewController = [UIViewController new];
        alertWindow.windowLevel = UIWindowLevelAlert + 1;
        [alertWindow makeKeyAndVisible];
        
        kw = alertWindow;
        if([kw respondsToSelector:@selector(topmostPresentedViewController)])
            root = [kw performSelector:@selector(topmostPresentedViewController)];
        else
            root = [kw rootViewController];
        root.modalPresentationStyle = UIModalPresentationFullScreen;
    });

    NSLog(@"[trolldecrypt] decrypt with flexdecrypt...");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *bundleID = app[@"bundleID"];
        NSString *name = app[@"name"];
        NSString *version = app[@"version"];
        NSString *executable = app[@"executable"];
        NSString *binaryName = [executable lastPathComponent];

        NSLog(@"[trolldecrypt] bundleID: %@", bundleID);
        NSLog(@"[trolldecrypt] name: %@", name);
        NSLog(@"[trolldecrypt] version: %@", version);
        NSLog(@"[trolldecrypt] executable: %@", executable);
        NSLog(@"[trolldecrypt] binaryName: %@", binaryName);

        // Show progress alert
        dispatch_async(dispatch_get_main_queue(), ^{
            alertController = [UIAlertController
                alertControllerWithTitle:@"Decrypting with FlexDecrypt"
                message:@"Please wait, this will take a few seconds..."
                preferredStyle:UIAlertControllerStyleAlert];
            [root presentViewController:alertController animated:YES completion:nil];
        });

        // Execute flexdecrypt
        NSString *flexdecryptPath = [[NSBundle mainBundle] pathForResource:@"flexdecrypt_bin" ofType:nil];
        if (!flexdecryptPath) {
            flexdecryptPath = @"./flexdecrypt_bin"; // Fallback to current directory
        }
        
        NSLog(@"[trolldecrypt] Using flexdecrypt at: %@", flexdecryptPath);
        NSLog(@"[trolldecrypt] Decrypting binary: %@", executable);
        
        // Run flexdecrypt command
        NSString *stdOut = nil;
        NSString *stdErr = nil;
        int result = spawnRoot(flexdecryptPath, @[executable], &stdOut, &stdErr);
        
        NSLog(@"[trolldecrypt] flexdecrypt result: %d", result);
        if (stdOut && stdOut.length > 0) {
            NSLog(@"[trolldecrypt] stdout: %@", stdOut);
        }
        if (stdErr && stdErr.length > 0) {
            NSLog(@"[trolldecrypt] stderr: %@", stdErr);
        }
        
        if (result != 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [alertController dismissViewControllerAnimated:NO completion:nil];
                errorController = [UIAlertController alertControllerWithTitle:@"FlexDecrypt Error" 
                    message:[NSString stringWithFormat:@"FlexDecrypt failed with error %d. stderr: %@", result, stdErr] 
                    preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [errorController dismissViewControllerAnimated:NO completion:nil];
                    [kw removeFromSuperview];
                    kw.hidden = YES;
                }];
                [errorController addAction:okAction];
                [root presentViewController:errorController animated:YES completion:nil];
            });
            return;
        }
        
        // Find the decrypted file in /tmp
        NSString *decryptedPath = [NSString stringWithFormat:@"/tmp/%@", binaryName];
        NSFileManager *fm = [NSFileManager defaultManager];
        
        if (![fm fileExistsAtPath:decryptedPath]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [alertController dismissViewControllerAnimated:NO completion:nil];
                errorController = [UIAlertController alertControllerWithTitle:@"FlexDecrypt Error" 
                    message:[NSString stringWithFormat:@"Decrypted file not found at: %@", decryptedPath] 
                    preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [errorController dismissViewControllerAnimated:NO completion:nil];
                    [kw removeFromSuperview];
                    kw.hidden = YES;
                }];
                [errorController addAction:okAction];
                [root presentViewController:errorController animated:YES completion:nil];
            });
            return;
        }
        
        NSLog(@"[trolldecrypt] Found decrypted file at: %@", decryptedPath);
        
        // Create IPA with decrypted binary
        createIPAWithFlexDecrypt(app, decryptedPath);
    });
}


NSArray *decryptedFileList(void) {
    NSMutableArray *files = [NSMutableArray array];
    NSMutableArray *fileNames = [NSMutableArray array];

    // iterate through all files in the Documents directory
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:docPath()];

    NSString *file;
    while (file = [directoryEnumerator nextObject]) {
        if ([[file pathExtension] isEqualToString:@"ipa"]) {
            NSString *filePath = [[docPath() stringByAppendingPathComponent:file] stringByStandardizingPath];

            NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:filePath error:nil];
            NSDate *modificationDate = fileAttributes[NSFileModificationDate];

            NSDictionary *fileInfo = @{@"fileName": file, @"modificationDate": modificationDate};
            [files addObject:fileInfo];
        }
    }

    // Sort the array based on modification date
    NSArray *sortedFiles = [files sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSDate *date1 = [obj1 objectForKey:@"modificationDate"];
        NSDate *date2 = [obj2 objectForKey:@"modificationDate"];
        return [date2 compare:date1];
    }];

    // Get the file names from the sorted array
    for (NSDictionary *fileInfo in sortedFiles) {
        [fileNames addObject:[fileInfo objectForKey:@"fileName"]];
    }

    return [fileNames copy];
}

NSString *docPath(void) {
    NSError * error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Documents/TrollDecrypt/decrypted" withIntermediateDirectories:YES attributes:nil error:&error];
    if (error != nil) {
        NSLog(@"[trolldecrypt] error creating directory: %@", error);
    }

    return @"/var/mobile/Documents/TrollDecrypt/decrypted";
}

void decryptAppWithPID(pid_t pid) {
    // generate App NSDictionary object to pass into decryptApp()
    // proc_pidpath(self.pid, buffer, sizeof(buffer));
    NSString *message = nil;
    NSString *error = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        alertWindow = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
        alertWindow.rootViewController = [UIViewController new];
        alertWindow.windowLevel = UIWindowLevelAlert + 1;
        [alertWindow makeKeyAndVisible];
        
        // Show a "Decrypting!" alert on the device and block the UI
            
        kw = alertWindow;
        if([kw respondsToSelector:@selector(topmostPresentedViewController)])
            root = [kw performSelector:@selector(topmostPresentedViewController)];
        else
            root = [kw rootViewController];
        root.modalPresentationStyle = UIModalPresentationFullScreen;
    });

    NSLog(@"[trolldecrypt] pid: %d", pid);

    char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
    proc_pidpath(pid, pathbuf, sizeof(pathbuf));

    NSString *executable = [NSString stringWithUTF8String:pathbuf];
    NSString *path = [executable stringByDeletingLastPathComponent];
    NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bundleID = infoPlist[@"CFBundleIdentifier"];

    if (!bundleID) {
        error = @"Error: -2";
        message = [NSString stringWithFormat:@"Failed to get bundle id for pid: %d", pid];
    }

    LSApplicationProxy *app = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
    if (!app) {
        error = @"Error: -3";
        message = [NSString stringWithFormat:@"Failed to get LSApplicationProxy for bundle id: %@", bundleID];
    }

    if (message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];
            NSLog(@"[trolldecrypt] failed to get bundleid for pid: %d", pid);

            errorController = [UIAlertController alertControllerWithTitle:error message:message preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"Ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSLog(@"[trolldecrypt] Ok action");
                [errorController dismissViewControllerAnimated:NO completion:nil];
                [kw removeFromSuperview];
                kw.hidden = YES;
            }];

            [errorController addAction:okAction];
            [root presentViewController:errorController animated:YES completion:nil];
        });
    }

    NSLog(@"[trolldecrypt] app: %@", app);

    NSDictionary *appInfo = @{
        @"bundleID":bundleID,
        @"name":[app atl_nameToDisplay],
        @"version":[app atl_shortVersionString],
        @"executable":executable
    };

    NSLog(@"[trolldecrypt] appInfo: %@", appInfo);

    dispatch_async(dispatch_get_main_queue(), ^{
        [alertController dismissViewControllerAnimated:NO completion:nil];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Decrypt" message:[NSString stringWithFormat:@"Decrypt %@?", appInfo[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *decrypt = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            decryptApp(appInfo);
        }];

        [alert addAction:decrypt];
        [alert addAction:cancel];
        
        [root presentViewController:alert animated:YES completion:nil];
    });
}

// void github_fetchLatedVersion(NSString *repo, void (^completionHandler)(NSString *latestVersion)) {
//     NSString *urlString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", repo];
//     NSURL *url = [NSURL URLWithString:urlString];

//     NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
//         if (!error) {
//             if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
//                 NSError *jsonError;
//                 NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

//                 if (!jsonError) {
//                     NSString *version = [json[@"tag_name"] stringByReplacingOccurrencesOfString:@"v" withString:@""];
//                     completionHandler(version);
//                 }
//             }
//         }
//     }];

//     [task resume];
// }

void fetchLatestTrollDecryptVersion(void (^completionHandler)(NSString *version)) {
    //github_fetchLatedVersion(@"donato-fiore/TrollDecrypt", completionHandler);
}

NSString *trollDecryptVersion(void) {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
}

void createIPAWithFlexDecrypt(NSDictionary *app, NSString *decryptedBinaryPath) {
    NSString *name = app[@"name"];
    NSString *version = app[@"version"];
    NSString *executable = app[@"executable"];
    NSString *binaryName = [executable lastPathComponent];
    
    // Get app path
    NSString *appPath = [executable stringByDeletingLastPathComponent];
    NSString *docPathStr = docPath();
    
    // Create IPA structure
    NSString *ipaDir = [NSString stringWithFormat:@"%@/ipa", docPathStr];
    NSString *payloadDir = [NSString stringWithFormat:@"%@/Payload", ipaDir];
    NSString *appDirName = [appPath lastPathComponent];
    NSString *appCopyDir = [NSString stringWithFormat:@"%@/%@", payloadDir, appDirName];
    NSString *ipaFile = [NSString stringWithFormat:@"%@/%@_%@_decrypted.ipa", docPathStr, name, version];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;
    
    // Clean up previous files
    [fm removeItemAtPath:ipaFile error:nil];
    [fm removeItemAtPath:ipaDir error:nil];
    
    // Ensure app copy directory doesn't exist - force remove with error checking
    if ([fm fileExistsAtPath:appCopyDir]) {
        NSLog(@"[trolldecrypt] Removing existing app copy directory: %@", appCopyDir);
        NSError *removeError;
        [fm removeItemAtPath:appCopyDir error:&removeError];
        if (removeError) {
            NSLog(@"[trolldecrypt] Warning: Could not remove existing directory: %@", removeError);
        }
    }
    
    // Create directories
    [fm createDirectoryAtPath:appCopyDir withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        NSLog(@"[trolldecrypt] Error creating app copy directory: %@", error);
        return;
    }
    
    NSLog(@"[trolldecrypt] Copying app from %@ to %@", appPath, appCopyDir);
    
    // Copy entire app directory
    [fm copyItemAtPath:appPath toPath:appCopyDir error:&error];
    if (error) {
        NSLog(@"[trolldecrypt] Error copying app directory: %@", error);
        // Try alternative approach - copy contents instead of directory
        NSLog(@"[trolldecrypt] Trying alternative copy approach...");
        [fm removeItemAtPath:appCopyDir error:nil];
        [fm createDirectoryAtPath:appCopyDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        // Get all items in the source app directory
        NSArray *sourceItems = [fm contentsOfDirectoryAtPath:appPath error:nil];
        for (NSString *item in sourceItems) {
            NSString *sourceItemPath = [appPath stringByAppendingPathComponent:item];
            NSString *destItemPath = [appCopyDir stringByAppendingPathComponent:item];
            [fm copyItemAtPath:sourceItemPath toPath:destItemPath error:nil];
        }
        NSLog(@"[trolldecrypt] Alternative copy approach completed");
    }
    
    // Replace the executable with decrypted version
    NSString *targetExecutable = [appCopyDir stringByAppendingPathComponent:binaryName];
    
    // Force remove existing executable
    if ([fm fileExistsAtPath:targetExecutable]) {
        NSLog(@"[trolldecrypt] Removing existing executable: %@", targetExecutable);
        NSError *removeError;
        [fm removeItemAtPath:targetExecutable error:&removeError];
        if (removeError) {
            NSLog(@"[trolldecrypt] Warning: Could not remove existing executable: %@", removeError);
        }
    }
    
    // Copy decrypted executable
    [fm copyItemAtPath:decryptedBinaryPath toPath:targetExecutable error:&error];
    if (error) {
        NSLog(@"[trolldecrypt] Error replacing executable: %@", error);
        // Try alternative approach - use NSData to force overwrite
        NSLog(@"[trolldecrypt] Trying alternative executable replacement...");
        NSData *decryptedData = [NSData dataWithContentsOfFile:decryptedBinaryPath];
        if (decryptedData) {
            BOOL writeSuccess = [decryptedData writeToFile:targetExecutable atomically:YES];
            if (writeSuccess) {
                NSLog(@"[trolldecrypt] Alternative executable replacement successful");
                error = nil; // Clear error since we succeeded
            } else {
                NSLog(@"[trolldecrypt] Alternative executable replacement failed");
            }
        } else {
            NSLog(@"[trolldecrypt] Could not read decrypted data");
        }
        
        if (error) {
            return;
        }
    }
    
    NSLog(@"[trolldecrypt] Replaced executable with decrypted version");
    
    // Create IPA file
    NSLog(@"[trolldecrypt] Creating IPA file: %@", ipaFile);
    BOOL success = [SSZipArchive createZipFileAtPath:ipaFile 
                                withContentsOfDirectory:ipaDir
                                keepParentDirectory:NO 
                                compressionLevel:1
                                password:nil
                                AES:NO
                                progressHandler:nil];
    
    if (success) {
        NSLog(@"[trolldecrypt] IPA created successfully: %@", ipaFile);
        
        // Clean up temporary files
        [fm removeItemAtPath:ipaDir error:nil];
        
        // Show success message
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];
            
            doneController = [UIAlertController alertControllerWithTitle:@"FlexDecrypt Complete!" 
                message:[NSString stringWithFormat:@"IPA file saved to:\n%@\n\nDecrypted using FlexDecrypt!", ipaFile] 
                preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [kw removeFromSuperview];
                kw.hidden = YES;
            }];
            [doneController addAction:okAction];
            
            if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"filza://"]]) {
                UIAlertAction *openAction = [UIAlertAction actionWithTitle:@"Show in Filza" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [kw removeFromSuperview];
                    kw.hidden = YES;
                    
                    NSString *urlString = [NSString stringWithFormat:@"filza://view%@", ipaFile];
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString] options:@{} completionHandler:nil];
                }];
                [doneController addAction:openAction];
            }
            
            [root presentViewController:doneController animated:YES completion:nil];
        });
    } else {
        NSLog(@"[trolldecrypt] Failed to create IPA file");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];
            errorController = [UIAlertController alertControllerWithTitle:@"FlexDecrypt Error" 
                message:@"Failed to create IPA file" 
                preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [errorController dismissViewControllerAnimated:NO completion:nil];
                [kw removeFromSuperview];
                kw.hidden = YES;
            }];
            [errorController addAction:okAction];
            [root presentViewController:errorController animated:YES completion:nil];
        });
    }
}
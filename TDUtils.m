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
        
        // First, run dlopen on the binary to load its dependencies
        NSLog(@"[trolldecrypt] Running dlopen on %@ to load dependencies", executable);
        NSString *dlopenPath = [[NSBundle mainBundle] pathForResource:@"dlopentool" ofType:nil];
        NSFileManager *fm = [NSFileManager defaultManager];
        
        if (dlopenPath && [fm fileExistsAtPath:dlopenPath]) {
            NSString *dlopenStdOut = nil;
            NSString *dlopenStdErr = nil;
            int dlopenResult = spawnRoot(dlopenPath, @[executable], &dlopenStdOut, &dlopenStdErr);
            
            if (dlopenResult == 0) {
                NSLog(@"[trolldecrypt] dlopen completed successfully for %@", executable);
                if (dlopenStdOut && dlopenStdOut.length > 0) {
                    NSLog(@"[trolldecrypt] dlopen stdout: %@", dlopenStdOut);
                }
            } else {
                NSLog(@"[trolldecrypt] dlopen failed for %@ (exit code: %d): %@", executable, dlopenResult, dlopenStdErr);
            }
        } else {
            NSLog(@"[trolldecrypt] dlopentool not found in app bundle, skipping dlopen step");
        }
        
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
        
        // Save decrypted binary to documents directory
        NSString *outputPath = [docPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@", name, version]];
        NSError *copyError;
        if ([fm copyItemAtPath:decryptedPath toPath:outputPath error:&copyError]) {
            NSLog(@"[trolldecrypt] Successfully saved decrypted binary: %@", outputPath);
            
            // Show success message after dismiss completes to avoid race conditions
            dispatch_async(dispatch_get_main_queue(), ^{
                [alertController dismissViewControllerAnimated:YES completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        UIAlertController *successController = [UIAlertController alertControllerWithTitle:@"Decryption Complete!"
                            message:[NSString stringWithFormat:@"Decrypted binary saved to:\n%@", outputPath]
                            preferredStyle:UIAlertControllerStyleAlert];
                        
                        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                            [kw removeFromSuperview];
                            kw.hidden = YES;
                        }];
                        [successController addAction:okAction];
                        
                        // Add Filza button if available
                        if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"filza://"]]) {
                            UIAlertAction *filzaAction = [UIAlertAction actionWithTitle:@"Open in Filza" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                [kw removeFromSuperview];
                                kw.hidden = YES;
                                
                                NSString *filzaURL = [NSString stringWithFormat:@"filza://view%@", outputPath];
                                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:filzaURL] options:@{} completionHandler:nil];
                            }];
                            [successController addAction:filzaAction];
                        }
                        
                        [root presentViewController:successController animated:YES completion:nil];
                    });
                }];
            });
        } else {
            NSLog(@"[trolldecrypt] Failed to copy decrypted file: %@", copyError.localizedDescription);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [alertController dismissViewControllerAnimated:NO completion:nil];
                errorController = [UIAlertController alertControllerWithTitle:@"Copy Error" 
                    message:[NSString stringWithFormat:@"Failed to save decrypted file: %@", copyError.localizedDescription] 
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
            // Don't dismiss alertController here, let decryptAllMachOInApp handle it
            decryptAllMachOInApp(appInfo);
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

// Enhanced decryption functions for all mach-o files in an app
void decryptAllMachOInApp(NSDictionary *app) {
    NSString *bundleID = app[@"bundleID"];
    NSString *name = app[@"name"];
    NSString *version = app[@"version"];
    
    // Show UI alert
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
        
        // Show progress alert with activity indicator
        alertController = [UIAlertController
            alertControllerWithTitle:@"Decrypting All Mach-O Files"
            message:@"Please wait, this will take a few minutes..."
            preferredStyle:UIAlertControllerStyleAlert];
        
        // Add activity indicator
        UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        [activityIndicator startAnimating];
        
        [alertController.view addSubview:activityIndicator];
        [NSLayoutConstraint activateConstraints:@[
            [activityIndicator.centerXAnchor constraintEqualToAnchor:alertController.view.centerXAnchor],
            [activityIndicator.topAnchor constraintEqualToAnchor:alertController.view.topAnchor constant:50]
        ]];
        
        [root presentViewController:alertController animated:YES completion:^{
            NSLog(@"[trolldecrypt] Progress alert presented successfully");
            // Force the alert to stay visible
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (alertController && alertController.view.window) {
                    NSLog(@"[trolldecrypt] Alert is visible and ready for updates");
                } else {
                    NSLog(@"[trolldecrypt] Alert failed to present properly");
                }
            });
        }];
    });
    
    NSLog(@"[trolldecrypt] Starting comprehensive decryption for %@", name);
    
    // Wait a moment for the alert to be fully presented
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Get the app bundle path
    LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
    if (!appProxy) {
        NSLog(@"[trolldecrypt] Failed to get app proxy for %@", bundleID);
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];
            UIAlertController *errorController = [UIAlertController alertControllerWithTitle:@"Error" 
                message:[NSString stringWithFormat:@"Failed to get app proxy for %@", bundleID] 
                preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [kw removeFromSuperview];
                kw.hidden = YES;
            }];
            [errorController addAction:okAction];
            [root presentViewController:errorController animated:YES completion:nil];
        });
        return;
    }
    
    NSString *appPath = [appProxy bundleURL].path;
    if (!appPath) {
        NSLog(@"[trolldecrypt] Failed to get app path for %@", bundleID);
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];
            UIAlertController *errorController = [UIAlertController alertControllerWithTitle:@"Error" 
                message:[NSString stringWithFormat:@"Failed to get app path for %@", bundleID] 
                preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [kw removeFromSuperview];
                kw.hidden = YES;
            }];
            [errorController addAction:okAction];
            [root presentViewController:errorController animated:YES completion:nil];
        });
        return;
    }
    
    NSLog(@"[trolldecrypt] App path: %@", appPath);
    
    // Find all mach-o files in the app
    NSArray *machOFiles = findAllMachOFiles(appPath);
    NSLog(@"[trolldecrypt] Found %lu mach-o files", (unsigned long)machOFiles.count);
    
    if (machOFiles.count == 0) {
        NSLog(@"[trolldecrypt] No mach-o files found in %@", appPath);
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];
            UIAlertController *errorController = [UIAlertController alertControllerWithTitle:@"Error" 
                message:[NSString stringWithFormat:@"No mach-o files found in %@", appPath] 
                preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [kw removeFromSuperview];
                kw.hidden = YES;
            }];
            [errorController addAction:okAction];
            [root presentViewController:errorController animated:YES completion:nil];
        });
        return;
    }
    
    // Create temporary working directory
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_decrypt_work", name]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:tempDir error:nil]; // Clean up any existing temp dir
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Copy the entire app bundle to temp directory
    NSString *tempAppPath = [tempDir stringByAppendingPathComponent:[appPath lastPathComponent]];
    NSError *copyError;
    if (![fm copyItemAtPath:appPath toPath:tempAppPath error:&copyError]) {
        NSLog(@"[trolldecrypt] Failed to copy app bundle: %@", copyError.localizedDescription);
        return;
    }
    
    NSLog(@"[trolldecrypt] Copied app bundle to: %@", tempAppPath);
    
    // Decrypt each mach-o file and replace it in the temp app bundle
    NSUInteger totalFiles = machOFiles.count;
    for (NSUInteger i = 0; i < machOFiles.count; i++) {
        NSString *machOFile = machOFiles[i];
        NSString *relativePath = [machOFile substringFromIndex:appPath.length + 1];
        NSString *tempMachOPath = [tempAppPath stringByAppendingPathComponent:relativePath];
        
        NSLog(@"[trolldecrypt] Decrypting: %@", relativePath);
        
        // Update progress in UI
        dispatch_async(dispatch_get_main_queue(), ^{
            if (alertController && alertController.isViewLoaded && alertController.view.window) {
                NSString *progressText = [NSString stringWithFormat:@"Decrypting %@\n\nProgress: %lu/%lu files\n\nPlease wait...", relativePath, (unsigned long)(i + 1), (unsigned long)totalFiles];
                alertController.message = progressText;
                NSLog(@"[trolldecrypt] Updated decryption progress: %@", progressText);
            } else {
                NSLog(@"[trolldecrypt] AlertController not available for decryption progress - isViewLoaded: %@, hasWindow: %@", 
                      alertController ? @(alertController.isViewLoaded) : @"nil", 
                      alertController ? @(alertController.view.window != nil) : @"nil");
            }
        });
        
        // Decrypt the file directly to the temp location (replacing original)
        decryptMachOFile(machOFile, tempMachOPath);
    }
    
    // Update progress for IPA creation
    dispatch_async(dispatch_get_main_queue(), ^{
        if (alertController && alertController.isViewLoaded) {
            alertController.message = @"Creating IPA file...\n\nThis may take a few minutes depending on app size.\n\nPlease wait...";
            NSLog(@"[trolldecrypt] Updated UI for IPA creation start");
        } else {
            NSLog(@"[trolldecrypt] AlertController not available for IPA creation start");
        }
    });
    
    // Create IPA from the modified app bundle
    NSString *ipaPath = [docPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@_decrypted.ipa", name, version]];
    createIPAFromAppBundle(tempAppPath, ipaPath);
    
    // Clean up temp directory
    [fm removeItemAtPath:tempDir error:nil];
    
    NSLog(@"[trolldecrypt] Comprehensive decryption completed for %@", name);
    NSLog(@"[trolldecrypt] IPA created at: %@", ipaPath);
    
    // Show success message after dismiss completes to avoid race conditions
    dispatch_async(dispatch_get_main_queue(), ^{
        [alertController dismissViewControllerAnimated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIAlertController *successController = [UIAlertController alertControllerWithTitle:@"Decryption Complete!"
                    message:[NSString stringWithFormat:@"IPA created successfully:\n%@", ipaPath]
                    preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [kw removeFromSuperview];
                    kw.hidden = YES;
                }];
                [successController addAction:okAction];
                
                // Add Filza button if available
                if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"filza://"]]) {
                    UIAlertAction *filzaAction = [UIAlertAction actionWithTitle:@"Open in Filza" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        [kw removeFromSuperview];
                        kw.hidden = YES;
                        
                        NSString *filzaURL = [NSString stringWithFormat:@"filza://view%@", ipaPath];
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:filzaURL] options:@{} completionHandler:nil];
                    }];
                    [successController addAction:filzaAction];
                }
                
                [root presentViewController:successController animated:YES completion:nil];
            });
        }];
    });
    }); // Close the dispatch_after block
}

NSArray *findAllMachOFiles(NSString *appPath) {
    NSMutableArray *machOFiles = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:appPath];
    NSString *file;
    
    while (file = [enumerator nextObject]) {
        NSString *fullPath = [appPath stringByAppendingPathComponent:file];
        
        // Skip certain directories that we don't want to process
        if ([file containsString:@".app/"] && ![file hasPrefix:[[appPath lastPathComponent] stringByAppendingString:@".app/"]]) {
            [enumerator skipDescendants];
            continue;
        }
        
        // Skip .dSYM directories
        if ([file containsString:@".dSYM/"]) {
            [enumerator skipDescendants];
            continue;
        }
        
        // Skip certain file types that are not mach-o
        NSString *extension = [file pathExtension];
        if ([extension isEqualToString:@"plist"] || 
            [extension isEqualToString:@"png"] || 
            [extension isEqualToString:@"jpg"] || 
            [extension isEqualToString:@"jpeg"] ||
            [extension isEqualToString:@"gif"] ||
            [extension isEqualToString:@"json"] ||
            [extension isEqualToString:@"txt"] ||
            [extension isEqualToString:@"xml"]) {
            continue;
        }
        
        if (isMachOFile(fullPath)) {
            NSLog(@"[trolldecrypt] Found mach-o file: %@", file);
            [machOFiles addObject:fullPath];
        }
    }
    
    return [machOFiles copy];
}

BOOL isMachOFile(NSString *filePath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Check if file exists and is not a directory
    BOOL isDirectory;
    if (![fm fileExistsAtPath:filePath isDirectory:&isDirectory] || isDirectory) {
        return NO;
    }
    
    // Check file extension
    NSString *extension = [filePath pathExtension];
    NSString *fileName = [filePath lastPathComponent];
    
    // Skip Unity metadata files and other non-executable files
    if ([fileName isEqualToString:@"CodeResources"] ||
        [fileName isEqualToString:@"globalgamemanagers"] ||
        [fileName isEqualToString:@"unity default resources"] ||
        [fileName isEqualToString:@"unity_builtin_extra"] ||
        [fileName hasPrefix:@"level"] ||
        [fileName hasSuffix:@"_CodeSignature"] ||
        [filePath containsString:@"_CodeSignature/"]) {
        return NO;
    }
    
    // Check for known mach-o extensions
    if ([extension isEqualToString:@"dylib"] || 
        [extension isEqualToString:@"so"] ||
        [fileName hasPrefix:@"lib"] ||
        [fileName hasSuffix:@".so"]) {
        return YES;
    }
    
    // Check for framework binaries (no extension, inside .framework)
    if ([extension isEqualToString:@""] && [filePath containsString:@".framework/"]) {
        // This is likely a framework binary
        return YES;
    }
    
    // Check if it's an executable (no extension)
    if ([extension isEqualToString:@""]) {
        // Read first 4 bytes to check for mach-o magic
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
        if (fileHandle) {
            NSData *magicData = [fileHandle readDataOfLength:4];
            [fileHandle closeFile];
            
            if (magicData.length >= 4) {
                const uint8_t *bytes = (const uint8_t *)magicData.bytes;
                uint32_t magic = *(uint32_t *)bytes;
                
                // Check for mach-o magic numbers
                if (magic == 0xfeedface || magic == 0xfeedfacf || magic == 0xcffaedfe || magic == 0xcefaedfe) {
                    return YES;
                }
            }
        }
    }
    
    return NO;
}

void decryptMachOFile(NSString *filePath, NSString *outputPath) {
    NSLog(@"[trolldecrypt] Decrypting mach-o file: %@", filePath);
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // First, run dlopen on the binary to load its dependencies
    NSLog(@"[trolldecrypt] Running dlopen on %@ to load dependencies", filePath);
    NSString *dlopenPath = [[NSBundle mainBundle] pathForResource:@"dlopentool" ofType:nil];
    
    if (dlopenPath && [fm fileExistsAtPath:dlopenPath]) {
        NSString *dlopenStdOut = nil;
        NSString *dlopenStdErr = nil;
        int dlopenResult = spawnRoot(dlopenPath, @[filePath], &dlopenStdOut, &dlopenStdErr);
        
        if (dlopenResult == 0) {
            NSLog(@"[trolldecrypt] dlopen completed successfully for %@", filePath);
            if (dlopenStdOut && dlopenStdOut.length > 0) {
                NSLog(@"[trolldecrypt] dlopen stdout: %@", dlopenStdOut);
            }
        } else {
            NSLog(@"[trolldecrypt] dlopen failed for %@ (exit code: %d): %@", filePath, dlopenResult, dlopenStdErr);
        }
    } else {
        NSLog(@"[trolldecrypt] dlopentool not found in app bundle, skipping dlopen step");
    }
    
    // Use flexdecrypt to decrypt the file
    NSString *flexdecryptPath = [[NSBundle mainBundle] pathForResource:@"flexdecrypt_bin" ofType:nil];
    if (!flexdecryptPath) {
        flexdecryptPath = @"./flexdecrypt_bin";
    }
    
    // Run flexdecrypt
    NSString *stdOut = nil;
    NSString *stdErr = nil;
    int result = spawnRoot(flexdecryptPath, @[filePath], &stdOut, &stdErr);
    
    if (result != 0) {
        NSLog(@"[trolldecrypt] FlexDecrypt failed for %@: %@", filePath, stdErr);
        return;
    }
    
    // Find the decrypted file (usually in /tmp with the same name)
    NSString *decryptedPath = [NSString stringWithFormat:@"/tmp/%@", [filePath lastPathComponent]];
    
    if ([fm fileExistsAtPath:decryptedPath]) {
        // Create output directory if it doesn't exist
        NSString *outputDir = [outputPath stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        // Remove existing file if it exists
        [fm removeItemAtPath:outputPath error:nil];
        
        // Copy decrypted file to output location
        NSError *error;
        if ([fm copyItemAtPath:decryptedPath toPath:outputPath error:&error]) {
            NSLog(@"[trolldecrypt] Successfully decrypted: %@ -> %@", filePath, outputPath);
            
            // Set proper permissions (executable)
            NSDictionary *attributes = @{NSFilePosixPermissions: @0755};
            [fm setAttributes:attributes ofItemAtPath:outputPath error:nil];
        } else {
            NSLog(@"[trolldecrypt] Failed to copy decrypted file: %@", error.localizedDescription);
        }
        
        // Clean up temp file
        [fm removeItemAtPath:decryptedPath error:nil];
    } else {
        NSLog(@"[trolldecrypt] Decrypted file not found at: %@", decryptedPath);
    }
}

void createIPAFromAppBundle(NSString *appBundlePath, NSString *ipaPath) {
    NSLog(@"[trolldecrypt] Creating IPA from app bundle: %@", appBundlePath);
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Create Payload directory in the same directory as the app bundle
    NSString *workDir = [appBundlePath stringByDeletingLastPathComponent];
    NSString *payloadDir = [workDir stringByAppendingPathComponent:@"Payload"];
    [fm removeItemAtPath:payloadDir error:nil]; // Clean up any existing payload dir
    [fm createDirectoryAtPath:payloadDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Copy app bundle to Payload directory
    NSString *payloadAppPath = [payloadDir stringByAppendingPathComponent:[appBundlePath lastPathComponent]];
    NSError *copyError;
    if (![fm copyItemAtPath:appBundlePath toPath:payloadAppPath error:&copyError]) {
        NSLog(@"[trolldecrypt] Failed to copy app bundle to Payload: %@", copyError.localizedDescription);
        return;
    }
    
    // Create IPA using SSZipArchive - zip the Payload folder directly
    NSLog(@"[trolldecrypt] Creating IPA using SSZipArchive...");
    BOOL success = [SSZipArchive createZipFileAtPath:ipaPath 
                                withContentsOfDirectory:payloadDir
                                keepParentDirectory:YES
                                compressionLevel:1
                                password:nil
                                AES:NO
                                progressHandler:^(NSUInteger entryNumber, NSUInteger total) {
                                    if (entryNumber % 50 == 0) { // Update more frequently
                                        NSLog(@"[trolldecrypt] IPA progress: %lu/%lu", (unsigned long)entryNumber, (unsigned long)total);
                                        // Update UI progress
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            if (alertController && alertController.isViewLoaded) {
                                                NSString *progressText = [NSString stringWithFormat:@"Creating IPA...\n\nProgress: %lu/%lu files\n\nPlease wait...", (unsigned long)entryNumber, (unsigned long)total];
                                                alertController.message = progressText;
                                                NSLog(@"[trolldecrypt] Updated UI progress: %@", progressText);
                                            } else {
                                                NSLog(@"[trolldecrypt] AlertController not available or not loaded");
                                            }
                                        });
                                    }
                                }];
    
    if (success) {
        NSLog(@"[trolldecrypt] IPA created successfully at: %@", ipaPath);
    } else {
        NSLog(@"[trolldecrypt] Failed to create IPA using SSZipArchive");
    }
    
    // Clean up Payload directory
    [fm removeItemAtPath:payloadDir error:nil];
}
#import "TDRootViewController.h"
#import "TDFileManagerViewController.h"
#import "TDUtils.h"
#import <spawn.h>
#import <rootless.h>
#import "appstoretrollerKiller/TSUtil.h"

@implementation TDRootViewController

- (void)loadView {
    [super loadView];

    self.apps = appList();
    self.title = @"TrollDecrypt";
	self.navigationController.navigationBar.prefersLargeTitles = YES;
    
    // Initialize hook preferences
    self.hookPrefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.trolldecrypt.hook"];
    
    // Right button - info
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(about:)];
    
    // Left button - folder
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(openDocs:)];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshApps:) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
}

- (void)viewDidAppear:(bool)animated {
    [super viewDidAppear:animated];

    fetchLatestTrollDecryptVersion(^(NSString *latestVersion) {
        NSString *currentVersion = trollDecryptVersion();
        NSComparisonResult result = [currentVersion compare:latestVersion options:NSNumericSearch];
        NSLog(@"[trolldecrypt] Current version: %@, Latest version: %@", currentVersion, latestVersion);
        if (result == NSOrderedAscending) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Update Available" message:@"An update for TrollDecrypt is available." preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
                UIAlertAction *update = [UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/donato-fiore/TrollDecrypt/releases/latest"]] options:@{} completionHandler:nil];
                }];

                [alert addAction:update];
                [alert addAction:cancel];
                [self presentViewController:alert animated:YES completion:nil];
            });
        }
    });
}

- (void)openDocs:(id)sender {
    TDFileManagerViewController *fmVC = [[TDFileManagerViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fmVC];
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)about:(id)sender {
    BOOL hookEnabled = [self.hookPrefs boolForKey:@"hookEnabled"];
    BOOL updatesEnabled = [self.hookPrefs boolForKey:@"updatesEnabled"];
    NSString *iosVersion = [self.hookPrefs objectForKey:@"iOSVersion"];
    if (iosVersion == nil || [iosVersion length] == 0) {
        iosVersion = @"99.0.0";
    }
    
    NSString *hookStatus = hookEnabled ? @"Enabled" : @"Disabled";
    NSString *updatesStatus = updatesEnabled ? @"Enabled" : @"Disabled (buyProduct only)";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TrollDecrypt JB" 
        message:[NSString stringWithFormat:@"Original by fiore\nModified by 34306 and khanhduytran0\nIcon by @super.user\nbfdecrypt by @bishopfox\ndumpdecrypted by @i0n1c\nUpdated for TrollStore by @wh1te4ever\nNathan and mineek for appstoretroller\n\n\nAppStore Spoof: %@\nSpoof iOS Version: %@\nShow Update (in AppStore): %@\n\nThis modified version support decrypt higher requirement iOS application.\nThanks to khanhduytran0, appstoretroller, lldb, modified by 34306.", hookStatus, iosVersion, updatesStatus]
        preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *dismiss = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil];
    
    if (hookEnabled) {
        UIAlertAction *toggleHook = [UIAlertAction actionWithTitle:@"Disable Hook" 
            style:UIAlertActionStyleDestructive 
            handler:^(UIAlertAction *action) {
                [self toggleAppStoreHook];
            }];
        
        UIAlertAction *setIOSVersion = [UIAlertAction actionWithTitle:@"Set iOS Version" 
            style:UIAlertActionStyleDefault 
            handler:^(UIAlertAction *action) {
                [self setIOSVersion];
            }];
        
        UIAlertAction *toggleUpdates = [UIAlertAction actionWithTitle:updatesEnabled ? @"Disable All Updates" : @"Enable All Updates" 
            style:UIAlertActionStyleDefault 
            handler:^(UIAlertAction *action) {
                [self toggleUpdatesEnabled];
            }];
        
        [alert addAction:toggleHook];
        [alert addAction:setIOSVersion];
        [alert addAction:toggleUpdates];
    } else {
        UIAlertAction *toggleHook = [UIAlertAction actionWithTitle:@"Enable Hook" 
            style:UIAlertActionStyleDefault 
            handler:^(UIAlertAction *action) {
                [self toggleAppStoreHook];
            }];
        [alert addAction:toggleHook];
    }
    
    [alert addAction:dismiss];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleAppStoreHook {
    BOOL currentState = [self.hookPrefs boolForKey:@"hookEnabled"];
    BOOL newState = !currentState;
    
    [self.hookPrefs setBool:newState forKey:@"hookEnabled"];
    [self.hookPrefs synchronize];
    
    NSString *status = newState ? @"enabled" : @"disabled";
    NSString *message = [NSString stringWithFormat:@"AppStore hook has been %@.\n\nClick Apply to restart daemons and activate changes.", status];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Hook Status Changed" 
        message:message 
        preferredStyle:UIAlertControllerStyleAlert];
    
    // UIAlertAction *ok = [UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil];
    
    UIAlertAction *apply = [UIAlertAction actionWithTitle:@"Apply" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction *action) {
            [self applyChanges];
        }];
    
    [alert addAction:apply];
    //[alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setIOSVersion {
    NSString *currentVersion = [self.hookPrefs objectForKey:@"iOSVersion"];
    if (currentVersion == nil || [currentVersion length] == 0) {
        currentVersion = @"99.0.0";
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Set iOS Version" 
        message:[NSString stringWithFormat:@"Enter the iOS version to spoof (e.g., 18.0.0).\n\nCurrent: %@", currentVersion]
        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"e.g., 18.0.0";
        textField.text = currentVersion;
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newVersion = alert.textFields.firstObject.text;
        if (newVersion && [newVersion length] > 0) {
            [self.hookPrefs setObject:newVersion forKey:@"iOSVersion"];
            [self.hookPrefs synchronize];
            
            UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"iOS Version Updated" 
                message:[NSString stringWithFormat:@"iOS version set to %@.\n\nClick Apply to restart daemons and activate changes.", newVersion]
                preferredStyle:UIAlertControllerStyleAlert];
            
            // UIAlertAction *ok = [UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil];
            UIAlertAction *apply = [UIAlertAction actionWithTitle:@"Apply" 
                style:UIAlertActionStyleDefault 
                handler:^(UIAlertAction *action) {
                    [self applyChanges];
                }];
            
            [successAlert addAction:apply];
            //[successAlert addAction:ok];
            [self presentViewController:successAlert animated:YES completion:nil];
        }
    }];
    
    [alert addAction:save];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleUpdatesEnabled {
    BOOL currentState = [self.hookPrefs boolForKey:@"updatesEnabled"];
    BOOL newState = !currentState;
    
    [self.hookPrefs setBool:newState forKey:@"updatesEnabled"];
    [self.hookPrefs synchronize];
    
    NSString *status = newState ? @"All app updates will now be spoofed" : @"Only buyProduct requests will be spoofed";
    NSString *message = [NSString stringWithFormat:@"%@.\n\nApply to activate changes.", status];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Updates Setting Changed" 
        message:message 
        preferredStyle:UIAlertControllerStyleAlert];
    
    // UIAlertAction *ok = [UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil];
    
    UIAlertAction *apply = [UIAlertAction actionWithTitle:@"Apply" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction *action) {
            [self applyChanges];
        }];
    
    [alert addAction:apply];
    //[alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applyChanges {
    // kill: appstored, installd, and AppStore app
    NSString *killerPath = ROOT_PATH_NS(@"/usr/local/bin/TDDaemonKiller");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *stdOut = nil;
        NSString *stdErr = nil;
        int result = spawnRoot(killerPath, @[], &stdOut, &stdErr);
        
        NSLog(@"[TrollDecrypt] appstoretrollerKiller result: %d", result);
        if (stdOut && stdOut.length > 0) {
            NSLog(@"[TrollDecrypt] stdout: %@", stdOut);
        }
        if (stdErr && stdErr.length > 0) {
            NSLog(@"[TrollDecrypt] stderr: %@", stdErr);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Changes Applied" 
                message:@"Daemons restarted successfully. Hook settings are now active."
                preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:ok];
            
            // Present on the topmost view controller
            UIViewController *topVC = self;
            while (topVC.presentedViewController) {
                topVC = topVC.presentedViewController;
            }
            [topVC presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)refreshApps:(UIRefreshControl *)refreshControl {
    self.apps = appList();
    [self.tableView reloadData];
    [refreshControl endRefreshing];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2; // Section 0: Apps, Section 1: Advanced
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { 
    if (section == 0) {
        return self.apps.count - 1; // Exclude the placeholder
    } else {
        return 1; // Advanced option
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"Installed Apps";
    } else {
        return @"Advanced";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"AppCell";
    UITableViewCell *cell;
    
    if (indexPath.section == 0) {
        cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        if (cell == nil) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    
        NSDictionary *app = self.apps[indexPath.row];

        cell.textLabel.text = app[@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", app[@"version"], app[@"bundleID"]];
        cell.imageView.image = [UIImage _applicationIconImageForBundleIdentifier:app[@"bundleID"] format:iconFormat() scale:[UIScreen mainScreen].scale];
    } else {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        
        cell.textLabel.text = @"Advanced";
        cell.detailTextLabel.text = @"Decrypt app from a specified PID";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UIAlertController *alert;
    
    if (indexPath.section == 0) {
        NSDictionary *app = self.apps[indexPath.row];

        alert = [UIAlertController alertControllerWithTitle:@"Decrypt" message:[NSString stringWithFormat:@"Decrypt %@?", app[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *decrypt = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            decryptApp(app);
        }];

        [alert addAction:decrypt];
        [alert addAction:cancel];
    } else {
        alert = [UIAlertController alertControllerWithTitle:@"Decrypt" message:@"Enter PID to decrypt" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"PID";
            textField.keyboardType = UIKeyboardTypeNumberPad;
        }];

        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *decrypt = [UIAlertAction actionWithTitle:@"Decrypt" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *pid = alert.textFields.firstObject.text;
            decryptAppWithPID([pid intValue]);
        }];

        [alert addAction:decrypt];
        [alert addAction:cancel];
    }

    [self presentViewController:alert animated:YES completion:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end


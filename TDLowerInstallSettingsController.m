#import "TDLowerInstallSettingsController.h"
#import <sys/utsname.h>

#define PLIST_PATH_Settings "/var/mobile/Library/Preferences/com.trolldecrypt.hook.plist"

@interface TDLowerInstallSettingsController ()
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UITextField *iosVersionField;
@property (nonatomic, strong) UITextField *deviceField;
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation TDLowerInstallSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self loadSettings];
}

- (void)setupUI {
    self.title = @"Lower Install Settings";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Create scroll view
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    // Create content view
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:contentView];
    
    // Enable switch
    UILabel *enabledLabel = [[UILabel alloc] init];
    enabledLabel.text = @"Enable Lower Install";
    enabledLabel.font = [UIFont systemFontOfSize:16];
    enabledLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:enabledLabel];
    
    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.enabledSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.enabledSwitch];
    
    // iOS Version field
    UILabel *iosVersionLabel = [[UILabel alloc] init];
    iosVersionLabel.text = @"iOS Version to Spoof";
    iosVersionLabel.font = [UIFont systemFontOfSize:16];
    iosVersionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:iosVersionLabel];
    
    self.iosVersionField = [[UITextField alloc] init];
    self.iosVersionField.borderStyle = UITextBorderStyleRoundedRect;
    self.iosVersionField.placeholder = @"e.g., 99.0.0";
    self.iosVersionField.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.iosVersionField];
    
    // Device field
    UILabel *deviceLabel = [[UILabel alloc] init];
    deviceLabel.text = @"Device to Spoof";
    deviceLabel.font = [UIFont systemFontOfSize:16];
    deviceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:deviceLabel];
    
    self.deviceField = [[UITextField alloc] init];
    self.deviceField.borderStyle = UITextBorderStyleRoundedRect;
    self.deviceField.placeholder = @"e.g., iPhone14,2";
    self.deviceField.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.deviceField];
    
    // Save button
    UIButton *saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [saveButton setTitle:@"Save Settings" forState:UIControlStateNormal];
    saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    saveButton.backgroundColor = [UIColor systemBlueColor];
    [saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    saveButton.layer.cornerRadius = 8;
    saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [saveButton addTarget:self action:@selector(saveSettings) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:saveButton];
    
    // Reset button
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [resetButton setTitle:@"Reset to Defaults" forState:UIControlStateNormal];
    resetButton.titleLabel.font = [UIFont systemFontOfSize:16];
    resetButton.backgroundColor = [UIColor systemRedColor];
    [resetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetButton.layer.cornerRadius = 8;
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resetButton addTarget:self action:@selector(resetSettings) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:resetButton];
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        // Scroll view constraints
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        // Content view constraints
        [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
        
        // Enabled switch constraints
        [enabledLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [enabledLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.enabledSwitch.centerYAnchor constraintEqualToAnchor:enabledLabel.centerYAnchor],
        [self.enabledSwitch.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // iOS Version constraints
        [iosVersionLabel.topAnchor constraintEqualToAnchor:enabledLabel.bottomAnchor constant:30],
        [iosVersionLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [iosVersionLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        [self.iosVersionField.topAnchor constraintEqualToAnchor:iosVersionLabel.bottomAnchor constant:8],
        [self.iosVersionField.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.iosVersionField.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.iosVersionField.heightAnchor constraintEqualToConstant:44],
        
        // Device constraints
        [deviceLabel.topAnchor constraintEqualToAnchor:self.iosVersionField.bottomAnchor constant:20],
        [deviceLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [deviceLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        [self.deviceField.topAnchor constraintEqualToAnchor:deviceLabel.bottomAnchor constant:8],
        [self.deviceField.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.deviceField.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.deviceField.heightAnchor constraintEqualToConstant:44],
        
        // Save button constraints
        [saveButton.topAnchor constraintEqualToAnchor:self.deviceField.bottomAnchor constant:40],
        [saveButton.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [saveButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [saveButton.heightAnchor constraintEqualToConstant:50],
        
        // Reset button constraints
        [resetButton.topAnchor constraintEqualToAnchor:saveButton.bottomAnchor constant:20],
        [resetButton.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [resetButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [resetButton.heightAnchor constraintEqualToConstant:44],
        [resetButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-20]
    ]];
}

- (void)loadSettings {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@PLIST_PATH_Settings];
    
    // Load enabled state
    BOOL enabled = [[prefs objectForKey:@"hookEnabled"] boolValue];
    self.enabledSwitch.on = enabled;
    
    // Load iOS version
    NSString *iosVersion = [prefs objectForKey:@"iOSVersion"];
    if (iosVersion && iosVersion.length > 0) {
        self.iosVersionField.text = iosVersion;
    } else {
        self.iosVersionField.text = @"99.0.0";
    }
    
    // Load device
    NSString *device = [prefs objectForKey:@"SpoofDevice"];
    if (device && device.length > 0) {
        self.deviceField.text = device;
    } else {
        // Get current device
        struct utsname systemInfo;
        uname(&systemInfo);
        self.deviceField.text = [NSString stringWithUTF8String:systemInfo.machine];
    }
}

- (void)switchChanged:(UISwitch *)sender {
    // Enable/disable text fields based on switch state
    self.iosVersionField.enabled = sender.on;
    self.deviceField.enabled = sender.on;
}

- (void)saveSettings {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:@PLIST_PATH_Settings] ?: [NSMutableDictionary dictionary];
    
    // Save enabled state
    [prefs setObject:@(self.enabledSwitch.on) forKey:@"hookEnabled"];
    
    // Save iOS version
    if (self.iosVersionField.text.length > 0) {
        [prefs setObject:self.iosVersionField.text forKey:@"iOSVersion"];
    }
    
    // Save device
    if (self.deviceField.text.length > 0) {
        [prefs setObject:self.deviceField.text forKey:@"SpoofDevice"];
    }
    
    // Write to file
    [prefs writeToFile:@PLIST_PATH_Settings atomically:YES];
    
    // Post notification to update tweak
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), 
                                        CFSTR("com.trolldecrypt.hook/SettingsChanged"), 
                                        NULL, NULL, YES);
    
    // Show success alert
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Settings Saved" 
                                                                   message:@"Lower Install settings have been saved successfully." 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Settings" 
                                                                   message:@"Are you sure you want to reset all settings to defaults?" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        // Reset to defaults
        struct utsname systemInfo;
        uname(&systemInfo);
        
        NSDictionary *defaults = @{
            @"hookEnabled": @YES,
            @"iOSVersion": @"99.0.0",
            @"SpoofDevice": [NSString stringWithUTF8String:systemInfo.machine]
        };
        [defaults writeToFile:@PLIST_PATH_Settings atomically:YES];
        
        // Reload UI
        [self loadSettings];
        
        // Post notification
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), 
                                            CFSTR("com.trolldecrypt.hook/SettingsChanged"), 
                                            NULL, NULL, YES);
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end

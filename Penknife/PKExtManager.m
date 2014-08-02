#import "PKExtManager.h"

static NSString* PKMasterShaURL = @"https://api.github.com/repos/penknife-io/ext/git/refs/heads/master";
static NSString* PKTreeListURL  = @"https://api.github.com/repos/penknife-io/ext/git/trees/master";
static NSString* PKRawFilePathURLTemplate = @"https://raw.githubusercontent.com/penknife-io/ext/%@/%@";

@implementation PKExtManager

+ (PKExtManager*) sharedExtManager {
    static PKExtManager* sharedExtManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedExtManager = [[PKExtManager alloc] init];
    });
    return sharedExtManager;
}

- (NSString*) extcacheDir       { return [@"~/.penknife/.extcache/" stringByStandardizingPath]; }
- (NSString*) extsAvailableFile { return [@"~/.penknife/.extcache/exts.available.json" stringByStandardizingPath]; }
- (NSString*) extsInstalledFile { return [@"~/.penknife/.extcache/exts.isntalled.json" stringByStandardizingPath]; }
- (NSString*) latestShaFile     { return [@"~/.penknife/.extcache/latest.sha.txt" stringByStandardizingPath]; }

- (void) downloadURL:(NSString*)urlString toPath:(NSString*)path {
    
}

- (void) getURL:(NSString*)urlString handleJSON:(void(^)(id json))handler {
    // come apple srsly
    NSURL* url = [NSURL URLWithString:urlString];
    NSURLRequest* req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5.0];
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               if (data) {
                                   NSError* __autoreleasing jsonError;
                                   id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                                   if (obj) {
                                       handler(obj);
                                   }
                                   else {
                                       NSLog(@"json error: %@", jsonError);
                                   }
                               }
                               else {
                                   NSLog(@"connection error: %@", connectionError);
                               }
                           }];
}

- (void) updateAvailableExts {
    if (self.updating) return;
    self.updating = YES;
    
    [self getURL:PKMasterShaURL handleJSON:^(NSDictionary* json) {
        NSString* newsha = [[json objectForKey:@"object"] objectForKey:@"sha"];
        
        // we need this to get the sha for the rawgithubcontent url (can't just use 'master' in case github's cache fails us)
        // we can also use it to quickly know if we need to fetch the full file dir.
        
        if ([newsha isEqualToString: self.latestSha]) {
            NSLog(@"no update found.");
            self.updating = NO;
            return;
        }
        
        NSLog(@"update found!");
        
        self.latestSha = newsha;
        [self saveLatestSha];
        
        [self getURL:PKTreeListURL handleJSON:^(NSDictionary* json) {
            NSMutableArray* newlist = [NSMutableArray array];
            for (NSDictionary* file in [json objectForKey:@"tree"]) {
                NSString* path = [file objectForKey:@"path"];
                if ([path hasSuffix:@".json"])
                    [newlist addObject:@{@"path": path, @"sha": [file objectForKey:@"sha"]}];
            }
            [self reflectAvailableExts:newlist];
            self.updating = NO;
        }];
    }];
}


- (void) reflectAvailableExts:(NSArray*)exts {
    for (NSDictionary* ext in exts) {
        NSLog(@"%@", ext);
        NSString* url = [NSString stringWithFormat:PKRawFilePathURLTemplate, self.latestSha, [ext objectForKey: @"path"]];
    }
}

- (void) saveInstalledExts:(NSArray*)exts {
    NSError* __autoreleasing error;
    NSData* data = [NSJSONSerialization dataWithJSONObject:exts options:NSJSONWritingPrettyPrinted error:&error];
    
    if (!data)
        NSLog(@"could not serialize json: %@", error);
    else
        [data writeToFile:[self extsInstalledFile] atomically:YES];
}

- (id) maybeJSONObjectFromFile:(NSString*)path {
    NSError* __autoreleasing error;
    NSData* data = [NSData dataWithContentsOfFile:[self extsInstalledFile] options:0 error:&error];
    id result = nil;
    if (data) result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    return result;
}

- (void) createDirectoryIfNeeded {
    NSError* __autoreleasing error;
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:[self extcacheDir] withIntermediateDirectories:YES attributes:nil error:&error];
    if (!success)
        NSLog(@"could not create extcache dir: %@", error);
}

- (void) loadCacheIntoMemory {
    self.installedExts = [self maybeJSONObjectFromFile:[self extsInstalledFile]];
    self.availableExts = [self maybeJSONObjectFromFile:[self extsAvailableFile]];
    self.latestSha = [NSString stringWithContentsOfFile:[self latestShaFile] encoding:NSUTF8StringEncoding error:NULL];
}

- (void) saveLatestSha {
    [self.latestSha writeToFile:[self latestShaFile] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void) setup {
    [self createDirectoryIfNeeded];
    [self loadCacheIntoMemory];
    [self updateAvailableExts];
}

@end
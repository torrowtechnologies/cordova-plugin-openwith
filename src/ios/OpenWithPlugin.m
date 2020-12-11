#import <UIKit/UIKit.h>
#import <Social/Social.h>
#import "ShareViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface ShareViewController : SLComposeServiceViewController <UIAlertViewDelegate> {
  NSFileManager *_fileManager;
  NSUserDefaults *_userDefaults;
  int _verbosityLevel;
}
@property (nonatomic,retain) NSFileManager *fileManager;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@property (nonatomic) int verbosityLevel;
@end

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize fileManager = _fileManager;
@synthesize userDefaults = _userDefaults;
@synthesize verbosityLevel = _verbosityLevel;

- (void) log:(int)level message:(NSString*)message {
  if (level >= self.verbosityLevel) {
    NSLog(@"[ShareViewController.m]%@", message);
  }
}

- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

- (void) setup {
  [self debug:@"[setup]"];

  self.fileManager = [NSFileManager defaultManager];
  self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
  self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
}

- (BOOL) isContentValid {
  return YES;
}

- (void) openURL:(nonnull NSURL *)url {
  SEL selector = NSSelectorFromString(@"openURL:options:completionHandler:");

  UIResponder* responder = self;
  while ((responder = [responder nextResponder]) != nil) {

    if([responder respondsToSelector:selector] == true) {
      NSMethodSignature *methodSignature = [responder methodSignatureForSelector:selector];
      NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];

      void (^completion)(BOOL success) = ^void(BOOL success) {};

      if (@available(iOS 13.0, *)) {
        UISceneOpenExternalURLOptions * options = [[UISceneOpenExternalURLOptions alloc] init];
        options.universalLinksOnly = false;

        [invocation setTarget: responder];
        [invocation setSelector: selector];
        [invocation setArgument: &url atIndex: 2];
        [invocation setArgument: &options atIndex:3];
        [invocation setArgument: &completion atIndex: 4];
        [invocation invoke];
        break;
      } else {
        NSDictionary<NSString *, id> *options = [NSDictionary dictionary];

        [invocation setTarget: responder];
        [invocation setSelector: selector];
        [invocation setArgument: &url atIndex: 2];
        [invocation setArgument: &options atIndex:3];
        [invocation setArgument: &completion atIndex: 4];
        [invocation invoke];
        break;
      }
    }
  }
}

- (void) viewDidAppear:(BOOL)animated {
  [self.view endEditing:YES];
  [self.view setHidden:YES];
  [self setup];
  [self debug:@"[viewDidAppear]"];

  __block int remainingAttachments = ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments.count;
  __block NSMutableArray *items = [[NSMutableArray alloc] init];
  __block NSDictionary *results = @{
    @"text" : self.contentText,
    @"items": items,
  };

  NSString *lastDataType = @"";

  for (NSItemProvider* itemProvider in ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments) {
    [self debug:[NSString stringWithFormat:@"item provider registered indentifiers = %@", itemProvider.registeredTypeIdentifiers]];

    // MOVIE
    if ([itemProvider hasItemConformingToTypeIdentifier:@"public.movie"]) {
      [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

      if (([lastDataType length] > 0) && ![lastDataType isEqualToString:@"FILE"]) {
        --remainingAttachments;
        continue;
      }

      lastDataType = [NSString stringWithFormat:@"FILE"];

      [itemProvider loadItemForTypeIdentifier:@"public.movie" options:nil completionHandler: ^(NSURL* item, NSError *error) {
        if(error != nil){
            --remainingAttachments;
            if (remainingAttachments == 0) {
              [self sendResults:results];
            }
        }
        NSString *fileUrl = [self saveFileToAppGroupFolder:item];
        NSString *suggestedName = item.lastPathComponent;

        NSString *uti = @"public.movie";
        NSString *registeredType = nil;

        if ([itemProvider.registeredTypeIdentifiers count] > 0) {
          registeredType = itemProvider.registeredTypeIdentifiers[0];
        } else {
          registeredType = uti;
        }

        NSString *mimeType =  [self mimeTypeFromUti:registeredType];
        NSDictionary *dict = @{
          @"text" : self.contentText,
          @"fileUrl" : fileUrl,
          @"uti"  : uti,
          @"utis" : itemProvider.registeredTypeIdentifiers,
          @"name" : suggestedName,
          @"type" : mimeType
        };

        [items addObject:dict];

        --remainingAttachments;
        if (remainingAttachments == 0) {
          [self sendResults:results];
        }
      }];
    }

    // IMAGE
    else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.image"]) {
      [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

      if (([lastDataType length] > 0) && ![lastDataType isEqualToString:@"FILE"]) {
        --remainingAttachments;
        continue;
      }
        
      lastDataType = [NSString stringWithFormat:@"FILE"];

      [itemProvider loadItemForTypeIdentifier:@"public.image" options:nil completionHandler: ^(id<NSSecureCoding> item, NSError *error){

        if(error != nil){
            --remainingAttachments;
            if (remainingAttachments == 0) {
              [self sendResults:results];
            }
        }

        NSData *data = [[NSData alloc] init];
          
        NSString *name = @"";
        NSString *fileUrl = @"";
          
        NSString *uti = @"";
        NSArray<NSString *> *utis = [NSArray new];
        if ([itemProvider.registeredTypeIdentifiers count] > 0) {
            uti = itemProvider.registeredTypeIdentifiers[0];
            utis = itemProvider.registeredTypeIdentifiers;
        }
        else {
            uti = @"public.image";
        }
          
        if([(NSObject*)item isKindOfClass:[NSURL class]]) {
            fileUrl = [self saveFileToAppGroupFolder:(NSURL*)item];
            name = [[(NSURL*)item path] lastPathComponent];
        }
        if([(NSObject*)item isKindOfClass:[UIImage class]]) {
            data = UIImagePNGRepresentation((UIImage*)item);
            name = uti;
        }
          
        if ([itemProvider respondsToSelector:NSSelectorFromString(@"getSuggestedName")])
        {
            name = [itemProvider valueForKey:@"suggestedName"];
        }
          
        NSString *base64 = [self base64forData: data];
          
        NSDictionary *dict = @{
          @"text" : self.contentText,
          @"data" : base64,
          @"fileUrl": fileUrl,
          @"uti"  : uti,
          @"utis" : itemProvider.registeredTypeIdentifiers,
          @"name" : name,
        };

        [items addObject:dict];

        --remainingAttachments;
        if (remainingAttachments == 0) {
          [self sendResults:results];
        }
      }];
    }

    // FILE
    else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.file-url"]) {
      [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

      if (([lastDataType length] > 0) && ![lastDataType isEqualToString:@"FILE"]) {
        --remainingAttachments;
        continue;
      }

      lastDataType = [NSString stringWithFormat:@"FILE"];

      [itemProvider loadItemForTypeIdentifier:@"public.file-url" options:nil completionHandler: ^(NSURL* item, NSError *error) {
        if(error != nil){
            --remainingAttachments;
            if (remainingAttachments == 0) {
              [self sendResults:results];
            }
        }
        NSString *fileUrl = [self saveFileToAppGroupFolder:item];
        NSString *suggestedName = item.lastPathComponent;

        NSString *uti = @"public.file-url";
        NSString *registeredType = nil;

        if ([itemProvider.registeredTypeIdentifiers count] > 0) {
          registeredType = itemProvider.registeredTypeIdentifiers[0];
        } else {
          registeredType = uti;
        }

        NSString *mimeType =  [self mimeTypeFromUti:registeredType];
        NSDictionary *dict = @{
          @"text" : self.contentText,
          @"fileUrl" : fileUrl,
          @"uti"  : uti,
          @"utis" : itemProvider.registeredTypeIdentifiers,
          @"name" : suggestedName,
          @"type" : mimeType
        };

        [items addObject:dict];

        --remainingAttachments;
        if (remainingAttachments == 0) {
          [self sendResults:results];
        }
      }];
    }

    // URL
    else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
      [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

      if ([lastDataType length] > 0 && ![lastDataType isEqualToString:@"URL"]) {
        --remainingAttachments;
        continue;
      }

      lastDataType = [NSString stringWithFormat:@"URL"];

      [itemProvider loadItemForTypeIdentifier:@"public.url" options:nil completionHandler: ^(NSURL* item, NSError *error) {
        if(error != nil){
            --remainingAttachments;
            if (remainingAttachments == 0) {
              [self sendResults:results];
            }
        }
        [self debug:[NSString stringWithFormat:@"public.url = %@", item]];

        NSString *uti = @"public.url";
        NSDictionary *dict = @{
          @"data" : item.absoluteString,
          @"uti": uti,
          @"utis": itemProvider.registeredTypeIdentifiers,
          @"name": @"",
          @"type": [self mimeTypeFromUti:uti],
        };

        [items addObject:dict];

        --remainingAttachments;
        if (remainingAttachments == 0) {
          [self sendResults:results];
        }
      }];
    }
    // TEXT
    else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.text"]) {
      [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

      if ([lastDataType length] > 0 && ![lastDataType isEqualToString:@"TEXT"]) {
        --remainingAttachments;
        continue;
      }

      lastDataType = [NSString stringWithFormat:@"TEXT"];

      [itemProvider loadItemForTypeIdentifier:@"public.text" options:nil completionHandler: ^(NSData* item, NSError *error) {
        if(error != nil){
            --remainingAttachments;
            if (remainingAttachments == 0) {
              [self sendResults:results];
            }
        }
        [self debug:[NSString stringWithFormat:@"public.text = %@", item]];

          NSString *data = [[NSString alloc] initWithData:item encoding: NSUTF8StringEncoding];

          NSString *uti = @"public.text";
        NSDictionary *dict = @{
          @"text" : self.contentText,
          @"data" : data,
          @"uti": uti,
          @"utis": itemProvider.registeredTypeIdentifiers,
          @"name": @"",
          @"type": [self mimeTypeFromUti:uti],
       };

        [items addObject:dict];

        --remainingAttachments;
        if (remainingAttachments == 0) {
          [self sendResults:results];
        }
      }];
    }

    // Data
    else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.data"]) {
      [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

      if ([lastDataType length] > 0 && ![lastDataType isEqualToString:@"TEXT"]) {
        --remainingAttachments;
        continue;
      }

      lastDataType = [NSString stringWithFormat:@"DATA"];

      [itemProvider loadItemForTypeIdentifier:@"public.data" options:nil completionHandler: ^(NSData* item, NSError *error) {
        if(error != nil){
            --remainingAttachments;
            if (remainingAttachments == 0) {
              [self sendResults:results];
            }
        }
        [self debug:[NSString stringWithFormat:@"public.data = %@", item]];

        NSString *base64 = [self base64forData: item];
          
          NSString *suggestedName = @"";
          if ([itemProvider respondsToSelector:NSSelectorFromString(@"getSuggestedName")]) {
              suggestedName = [itemProvider valueForKey:@"suggestedName"];
          }
          
        NSString *uti = @"public.data";
        NSDictionary *dict = @{
          @"text" : self.contentText,
          @"data" : base64,
          @"uti": uti,
          @"utis": itemProvider.registeredTypeIdentifiers,
          @"name": suggestedName,
          @"type": [self mimeTypeFromUti:uti],
       };

        [items addObject:dict];

        --remainingAttachments;
        if (remainingAttachments == 0) {
          [self sendResults:results];
        }
      }];
    }

    // Unhandled data type
    else {
      --remainingAttachments;
      if (remainingAttachments == 0) {
        [self sendResults:results];
      }
    }
  }
}

- (void) sendResults: (NSDictionary*)results {
  [self.userDefaults setObject:results forKey:@"shared"];
  [self.userDefaults synchronize];
  NSObject *object = [self.userDefaults objectForKey:@"shared"];
  // Emit a URL that opens the cordova app
  NSString *url = [NSString stringWithFormat:@"%@://shared", SHAREEXT_URL_SCHEME];
  [self openURL:[NSURL URLWithString:url]];

  // Shut down the extension
  [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

 - (void) didSelectPost {
   [self debug:@"[didSelectPost]"];
 }

- (NSArray*) configurationItems {
  // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
  return @[];
}

- (NSString *) mimeTypeFromUti: (NSString*)uti {
  if (uti == nil) { return nil; }

  CFStringRef cret = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)uti, kUTTagClassMIMEType);
  NSString *ret = (__bridge_transfer NSString *)cret;

  return ret == nil ? uti : ret;
}

- (NSString *) saveDataToAppGroupFolder: (NSData*)data {
    NSURL *targetUrl = [[self.fileManager containerURLForSecurityApplicationGroupIdentifier:SHAREEXT_GROUP_IDENTIFIER] URLByAppendingPathComponent: [NSString stringWithFormat:@"file-%d", rand()]];
    [data writeToURL:targetUrl atomically: true];

  return targetUrl.absoluteString;
}

- (NSString *) saveFileToAppGroupFolder: (NSURL*)url {
  NSURL *targetUrl = [[self.fileManager containerURLForSecurityApplicationGroupIdentifier:SHAREEXT_GROUP_IDENTIFIER] URLByAppendingPathComponent:url.lastPathComponent];
  [self.fileManager copyItemAtURL:url toURL:targetUrl error:nil];

  return targetUrl.absoluteString;
}

- (NSString*) base64forData:(NSData*)theData {
    const uint8_t* input = (const uint8_t*)[theData bytes];
    NSInteger length = [theData length];

    static char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

    NSMutableData* data = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
    uint8_t* output = (uint8_t*)data.mutableBytes;

    NSInteger i;
    for (i=0; i < length; i += 3) {
        NSInteger value = 0;
        NSInteger j;
        for (j = i; j < (i + 3); j++) {
            value <<= 8;

            if (j < length) {
                value |= (0xFF & input[j]);
            }
        }

        NSInteger theIndex = (i / 3) * 4;
        output[theIndex + 0] =                    table[(value >> 18) & 0x3F];
        output[theIndex + 1] =                    table[(value >> 12) & 0x3F];
        output[theIndex + 2] = (i + 1) < length ? table[(value >> 6)  & 0x3F] : '=';
        output[theIndex + 3] = (i + 2) < length ? table[(value >> 0)  & 0x3F] : '=';
    }

    return [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
}

@end

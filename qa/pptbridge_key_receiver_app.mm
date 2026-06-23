#import <Cocoa/Cocoa.h>

static FILE *gLog = nullptr;

static void AppendLog(NSString *line)
{
  if (!gLog) {
    gLog = fopen("/tmp/pptbridge-key-receiver.log", "a");
  }
  if (!gLog) {
    return;
  }
  fprintf(gLog, "%s\n", [line UTF8String]);
  fflush(gLog);
}

static NSString *KeyName(unsigned short keyCode)
{
  switch (keyCode) {
  case 116: return @"pageup";
  case 121: return @"pagedown";
  case 123: return @"left";
  case 124: return @"right";
  default: return [NSString stringWithFormat:@"keycode-%hu", keyCode];
  }
}

@interface KeyReceiverView : NSView
@end

@implementation KeyReceiverView
- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (void)viewDidMoveToWindow
{
  [self.window makeFirstResponder:self];
}

- (void)keyDown:(NSEvent *)event
{
  AppendLog([NSString stringWithFormat:@"down %@", KeyName(event.keyCode)]);
}

- (void)keyUp:(NSEvent *)event
{
  AppendLog([NSString stringWithFormat:@"up %@", KeyName(event.keyCode)]);
}

- (void)drawRect:(NSRect)dirtyRect
{
  [[NSColor windowBackgroundColor] setFill];
  NSRectFill(dirtyRect);
  NSDictionary *attrs = @{
    NSFontAttributeName: [NSFont systemFontOfSize:18.0],
    NSForegroundColorAttributeName: [NSColor labelColor],
  };
  [@"PPTBridge key receiver\nSend Left/Right/PageUp/PageDown now"
    drawAtPoint:NSMakePoint(24, 76)
    withAttributes:attrs];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  (void)notification;
  AppendLog(@"ready");
  NSRect frame = NSMakeRect(0, 0, 520, 180);
  self.window = [[NSWindow alloc]
    initWithContentRect:frame
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
    backing:NSBackingStoreBuffered
    defer:NO];
  self.window.title = @"PPTBridge Key Receiver";
  [self.window center];
  KeyReceiverView *view = [[KeyReceiverView alloc] initWithFrame:frame];
  self.window.contentView = view;
  [self.window makeKeyAndOrderFront:nil];
  [self.window makeFirstResponder:view];
  [NSApp activateIgnoringOtherApps:YES];
  [[NSRunningApplication currentApplication] activateWithOptions:
    NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps];

  [NSTimer scheduledTimerWithTimeInterval:0.5
    repeats:YES
    block:^(NSTimer *timer) {
      (void)timer;
      [self.window makeKeyAndOrderFront:nil];
      [self.window makeFirstResponder:view];
      [NSApp activateIgnoringOtherApps:YES];
      [[NSRunningApplication currentApplication] activateWithOptions:
        NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps];
    }];

  [NSTimer scheduledTimerWithTimeInterval:20.0
    repeats:NO
    block:^(NSTimer *timer) {
      (void)timer;
      AppendLog(@"done");
      [NSApp terminate:nil];
    }];
}
@end

int main(int argc, const char **argv)
{
  (void)argc;
  (void)argv;
  @autoreleasepool {
    remove("/tmp/pptbridge-key-receiver.log");
    [NSApplication sharedApplication];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    [NSApp setDelegate:delegate];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp run];
    if (gLog) {
      fclose(gLog);
    }
  }
  return 0;
}

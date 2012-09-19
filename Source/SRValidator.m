//
//  SRValidator.h
//  ShortcutRecorder
//
//  Copyright 2006-2012 Contributors. All rights reserved.
//
//  License: BSD
//
//  Contributors:
//      David Dauer
//      Jesper
//      Jamie Kirkpatrick
//      Andy Kim
//      Silvio Rizzi

#import "SRValidator.h"
#import "SRCommon.h"

@implementation SRValidator

//----------------------------------------------------------
// iinitWithDelegate:
//----------------------------------------------------------
- (id)initWithDelegate:(id)theDelegate;
{
    self = [super init];
    if (!self)
        return nil;

    [self setDelegate:theDelegate];

    return self;
}

//----------------------------------------------------------
// isKeyCode:andFlagsTaken:error:
//----------------------------------------------------------
- (BOOL)isKeyCode:(NSInteger)keyCode andFlagsTaken:(NSUInteger)flags error:(NSError **)error;
{
    // if we have a delegate, it goes first...
    if (delegate)
    {
        NSString *delegateReason = nil;
        if ([delegate shortcutValidator:self
                              isKeyCode:keyCode
                          andFlagsTaken:SRCarbonToCocoaFlags(flags)
                                 reason:&delegateReason])
        {
            if (error)
            {
                BOOL isASCIIOnly = [delegate shortcutValidatorShouldUseASCIIStringForKeyCodes:self];
                NSString *shortcut = isASCIIOnly ? SRReadableASCIIStringForCarbonModifierFlagsAndKeyCode(flags, keyCode) : SRReadableStringForCarbonModifierFlagsAndKeyCode(flags, keyCode);
                NSString *description = [NSString stringWithFormat:
                                                      SRLoc(@"The key combination %@ can't be used!"),
                                                      shortcut];
                NSString *recoverySuggestion = [NSString stringWithFormat:
                                                             SRLoc(@"The key combination \"%@\" can't be used because %@."),
                                                             shortcut,
                                                             (delegateReason && [delegateReason length]) ? delegateReason : @"it's already used"];
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                                           description, NSLocalizedDescriptionKey,
                                                           recoverySuggestion, NSLocalizedRecoverySuggestionErrorKey,
                                                           [NSArray arrayWithObject:@"OK"], NSLocalizedRecoveryOptionsErrorKey, // Is this needed? Shouldn't it show 'OK' by default? -AK
                                                           nil];
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
            }
            return YES;
        }
    }

    // then our implementation...
    CFArrayRef tempArray = NULL;
    OSStatus err = noErr;

    // get global hot keys...
    err = CopySymbolicHotKeys(&tempArray);

    if (err != noErr) return YES;

    // Not copying the array like this results in a leak on according to the Leaks Instrumen
    NSArray *globalHotKeys = [NSArray arrayWithArray:(NSArray *)tempArray];

    if (tempArray) CFRelease(tempArray);

    NSEnumerator *globalHotKeysEnumerator = [globalHotKeys objectEnumerator];
    NSDictionary *globalHotKeyInfoDictionary;
    int32_t globalHotKeyFlags;
    NSInteger globalHotKeyCharCode;
    BOOL globalCommandMod = NO, globalOptionMod = NO, globalShiftMod = NO, globalCtrlMod = NO;
    BOOL localCommandMod = NO, localOptionMod = NO, localShiftMod = NO, localCtrlMod = NO;

    // Prepare local carbon comparison flags
    if (flags & cmdKey) localCommandMod = YES;
    if (flags & optionKey) localOptionMod = YES;
    if (flags & shiftKey) localShiftMod = YES;
    if (flags & controlKey) localCtrlMod = YES;

    return [self isKeyCode:keyCode andFlags:flags takenInMenu:[NSApp mainMenu] error:error];
}

//----------------------------------------------------------
// isKeyCode:andFlags:takenInMenu:error:
//----------------------------------------------------------
- (BOOL)isKeyCode:(NSInteger)keyCode andFlags:(NSUInteger)flags takenInMenu:(NSMenu *)menu error:(NSError **)error;
{
    NSArray *menuItemsArray = [menu itemArray];
    NSEnumerator *menuItemsEnumerator = [menuItemsArray objectEnumerator];
    NSMenuItem *menuItem;
    NSUInteger menuItemModifierFlags;
    NSString *menuItemKeyEquivalent;

    BOOL menuItemCommandMod = NO, menuItemOptionMod = NO, menuItemShiftMod = NO, menuItemCtrlMod = NO;
    BOOL localCommandMod = NO, localOptionMod = NO, localShiftMod = NO, localCtrlMod = NO;

    // Prepare local carbon comparison flags
    if (flags & cmdKey) localCommandMod = YES;
    if (flags & optionKey) localOptionMod = YES;
    if (flags & shiftKey) localShiftMod = YES;
    if (flags & controlKey) localCtrlMod = YES;

    while ((menuItem = [menuItemsEnumerator nextObject]))
    {
        // rescurse into all submenus...
        if ([menuItem hasSubmenu])
        {
            if ([self isKeyCode:keyCode andFlags:flags takenInMenu:[menuItem submenu] error:error])
            {
                return YES;
            }
        }

        if ((menuItemKeyEquivalent = [menuItem keyEquivalent])
            && (![menuItemKeyEquivalent isEqualToString:@""]))
        {
            menuItemCommandMod = NO;
            menuItemOptionMod = NO;
            menuItemShiftMod = NO;
            menuItemCtrlMod = NO;

            menuItemModifierFlags = [menuItem keyEquivalentModifierMask];

            // better handling of shift key masked key equivalents
            if (![[menuItemKeyEquivalent lowercaseString] isEqualToString:[menuItemKeyEquivalent uppercaseString]] &&
                [[menuItemKeyEquivalent uppercaseString] isEqualToString:menuItemKeyEquivalent])
            {
                menuItemKeyEquivalent = [menuItemKeyEquivalent lowercaseString];
                menuItemModifierFlags = menuItemModifierFlags | NSShiftKeyMask;
            }
            if (menuItemModifierFlags & NSCommandKeyMask) menuItemCommandMod = YES;
            if (menuItemModifierFlags & NSAlternateKeyMask) menuItemOptionMod = YES;
            if (menuItemModifierFlags & NSShiftKeyMask) menuItemShiftMod = YES;
            if (menuItemModifierFlags & NSControlKeyMask) menuItemCtrlMod = YES;

            NSString *localKeyString = nil;
            if ([delegate shortcutValidatorShouldUseASCIIStringForKeyCodes:self])
                localKeyString = SRASCIIStringForKeyCode(keyCode);
            else
                localKeyString = SRStringForKeyCode(keyCode);

            // Compare translated keyCode and modifier flags
            if (([[menuItemKeyEquivalent uppercaseString] isEqualToString:localKeyString])
                && (menuItemCommandMod == localCommandMod)
                && (menuItemOptionMod == localOptionMod)
                && (menuItemShiftMod == localShiftMod)
                && (menuItemCtrlMod == localCtrlMod))
            {
                if (error)
                {
                    BOOL isASCIIOnly = [delegate shortcutValidatorShouldUseASCIIStringForKeyCodes:self];
                    NSString *shortcut = isASCIIOnly ? SRReadableASCIIStringForCocoaModifierFlagsAndKeyCode(menuItemModifierFlags, keyCode) : SRReadableStringForCocoaModifierFlagsAndKeyCode(menuItemModifierFlags, keyCode);
                    NSString *description = [NSString stringWithFormat:
                                                          SRLoc(@"The key combination %@ can't be used!"),
                                                          shortcut];
                    NSString *recoverySuggestion = [NSString stringWithFormat:
                                                                 SRLoc(@"The key combination \"%@\" can't be used because it's already used by the menu item \"%@\"."),
                                                                 shortcut,
                                                                 [menuItem title]];
                    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                                               description, NSLocalizedDescriptionKey,
                                                               recoverySuggestion, NSLocalizedRecoverySuggestionErrorKey,
                                                               [NSArray arrayWithObject:@"OK"], NSLocalizedRecoveryOptionsErrorKey,
                                                               nil];
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
                }
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark -
#pragma mark accessors

//----------------------------------------------------------
//  delegate
//----------------------------------------------------------
- (id)delegate
{
    return delegate;
}

- (void)setDelegate:(id)theDelegate
{
    delegate = theDelegate; // Standard delegate pattern does not retain the delegate
}

@end

#pragma mark -
#pragma mark default delegate implementation

@implementation NSObject (SRValidation)

//----------------------------------------------------------
// shortcutValidator:isKeyCode:andFlagsTaken:reason:
//----------------------------------------------------------
- (BOOL)shortcutValidator:(SRValidator *)validator isKeyCode:(NSInteger)keyCode andFlagsTaken:(NSUInteger)flags reason:(NSString **)aReason;
{
    return NO;
}

- (BOOL)shortcutValidatorShouldCheckMenu:(SRValidator *)validator
{
    return NO;
}

- (BOOL)shortcutValidatorShouldUseASCIIStringForKeyCodes:(SRValidator *)validator
{
    return NO;
}

@end

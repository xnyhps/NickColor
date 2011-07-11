/* 
 * NickColor is a nick coloring plugin for Adium.
 * Copyright (C) 2011 Thijs Alkemade
 * 
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "AICANPlugin.h"

#import <Adium/AIContentObject.h>
#import <Adium/AIChat.h>
#import <Adium/AICorePluginLoader.h>

// This plugin has some tricky dependencies on stuff not in Adium.framework...
@interface NSColor (AIColorAdditions_ObjectColor)

+ (id)colorWithHTMLString:(NSString *)str;
+ (NSString *)representedColorForObject: (id)anObject withValidColors: (NSArray *)validColors;

@end

@class AIWebkitMessageViewStyle;
@class AIWebKitMessageViewPlugin;

@interface AIWebkitMessageViewStyle : NSObject
- (NSArray *)validSenderColors;
@end

@interface AIWebKitMessageViewPlugin : NSObject
- (AIWebkitMessageViewStyle *) currentMessageStyleForChat:(AIChat *)chat;
@end



@implementation AICANPlugin

#pragma mark AIPlugin

- (void)installPlugin
{
	[[adium contentController] registerHTMLContentFilter:self direction:AIFilterIncoming];
	[[adium contentController] registerHTMLContentFilter:self direction:AIFilterOutgoing];
}

- (void)uninstallPlugin
{
	[[adium contentController] unregisterHTMLContentFilter:self];
}

#pragma mark AIHTMLContentFilter

/* Sort by length, so we color longer names first in case very short names form substrings of longer nicks.
 */
NSComparisonResult compareContacts(id a, id b, void *context) {
	AIListObject *contactA = (AIListObject *)a;
	AIListObject *contactB = (AIListObject *)b;
	AIChat *chat = (AIChat *)context;
	
	NSUInteger lenA = [[chat displayNameForContact:contactA] length];
	NSUInteger lenB = [[chat displayNameForContact:contactB] length];
	
	return lenA > lenB ? NSOrderedAscending : (lenA < lenB ? NSOrderedDescending : NSOrderedSame);
}

- (NSString *)filterHTMLString:(NSString *)inHTMLString content:(AIContentObject *)content
{
	if (!content.chat.isGroupChat) {
		return inHTMLString;
	}
	
	AIChat *chat = content.chat;
		
	// We need this ugly runtime hack to get the validSenderColors
	AIWebKitMessageViewPlugin *webKitPlugin = (AIWebKitMessageViewPlugin *)[adium.componentLoader pluginWithClassName:@"AIWebKitMessageViewPlugin"];
	
	// Ensure we don't crash, even if stuff got changed
	if (!webKitPlugin) {
		NSLog(@" *** AICANPlugin: failed to find webKitPlugin!");
		return inHTMLString;
	}
	
	if (![webKitPlugin respondsToSelector:@selector(currentMessageStyleForChat:)]) {
		NSLog(@" *** AICANPlugin: webKitPlugin doesn't respond to -currentMessageStyleForChat:!");
		return inHTMLString;
	}
	
	AIWebkitMessageViewStyle *viewStyle = [webKitPlugin currentMessageStyleForChat:chat];
	
	if (![viewStyle respondsToSelector:@selector(validSenderColors)]) {
		NSLog(@" *** AICANPlugin: viewStyle doesn't respond to -validSenderColors!");
		return inHTMLString;
	}
	
	NSArray *validSenderColors = [viewStyle validSenderColors];
	
	NSArray *contacts = [[chat visibleContainedObjects] sortedArrayUsingFunction:compareContacts context:chat];
	
	NSString *result = inHTMLString;
	
	// Enumerate over contacts first, so we don't end up replacing inside the <span> tags again.
	for (AIListObject *contact in contacts) {
		
		NSMutableArray *fragments = [[result componentsSeparatedByString:@"<"] mutableCopy];
		
		NSUInteger i;
		
		for (i = 0; i < [fragments count]; i++) {
			
			NSString *fragment = [fragments objectAtIndex:i];
			
			/* This could either start with the contents of an HTML tag, and then some text,
			 * or it's the first element, then the text starts immediately.
			 */
			NSRange endOfTag = [fragment rangeOfString:@">"];
			
			NSRange contentRange;
			
			if (endOfTag.location == NSNotFound) {
				contentRange = NSMakeRange(0, [fragment length]);
			} else {
				contentRange = NSMakeRange(endOfTag.location + endOfTag.length, [fragment length] - (endOfTag.location + endOfTag.length));
			}
			
			NSString *newFragment = [fragment stringByReplacingOccurrencesOfString:[chat displayNameForContact:contact]
																		withString:[NSString stringWithFormat:@"<span style=\"color: %@\">%@</span>",
																					[NSColor representedColorForObject:contact.UID
																									   withValidColors:validSenderColors],
																					[chat displayNameForContact:contact]]
																		   options:0
																			 range:contentRange];
			[fragments replaceObjectAtIndex:i withObject:newFragment];
		}
		
		result = [fragments componentsJoinedByString:@"<"];
	}
	
	return result;
}

- (CGFloat)filterPriority
{
	return 0.0f;
}

#pragma mark AIPluginInfo

- (NSString *)pluginAuthor
{
	return @"Thijs Alkemade";
}

- (NSString *)pluginDescription
{
	return @"Colors nicknames used in group chats with their sender's color.";
}

- (NSString *)pluginVersion
{
	return @"0.0.1";
}

- (NSString *)pluginURL
{
	return nil;
}

@end

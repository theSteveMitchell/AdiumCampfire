//
//  MSTCampfireAccount.m
//  AdiumCampfire
//
//  Created by Marek Stępniowski on 10-03-10.
//  Copyright 2010 Apple Inc. All rights reserved.
//

#import "MSCampfireAccount.h"
#import "MSCampfireRoom.h"
#import "NSString+SBJSON.h"
#import <Adium/ESDebugAILog.h>
#import <Adium/AIListBookmark.h>
#import <Adium/AIChat.h>
#import <AIUtilities/AIApplicationAdditions.h>
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIStatusControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIContactObserverManager.h>
#import <Adium/AISharedAdium.h>
#import <Adium/AIContentMessage.h>
#import <objc/runtime.h>

@implementation MSCampfireAccount

static char urlContact;

- (void)initAccount
{
	[super initAccount];
  
  engine = nil;
  _rooms = [[NSMutableDictionary alloc] init];
  lastRoomsUpdate = nil;
  updatedRoomsCount = 0;
  authenticatedUserId = -1;
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(chatDidOpen:)
                                               name:Chat_DidOpen
                                             object:nil];
  
  if (!self.host && self.defaultServer) {
    [self setPreference:self.defaultServer forKey:KEY_CONNECT_HOST group:GROUP_ACCOUNT_STATUS];
  }
     
  AILogWithSignature(@"Initialized CampFire domain %@", self.UID);
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
}

- (NSString *)defaultServer
{
    return self.UID;
}

- (void)connect
{
  AILogWithSignature(@"%@ connecting to Campfire", self);
	[super connect];
    
  [self setConnectionProgress:[NSNumber numberWithDouble:0.3] message:@"Connecting"];

   engine = nil;

  engine = [[MSCampfireEngine alloc] initWithDomain:self.UID key:self.passwordWhileConnected delegate:self];
  
  [engine getInformationForAuthenticatedUser];
  [engine getRooms];
}

- (void)disconnect
{
  [super disconnect];
   lastRoomsUpdate = nil;
   engine = nil;
  
  [self didDisconnect];
}

#pragma mark AIAccount methods
- (BOOL)maySendMessageToInvisibleContact:(AIListContact *)inContact
{
	return NO;
}

- (BOOL)openChat:(AIChat *)chat
{	
  chat.hideUserIconAndStatus = YES;
  // That fucker is setting status to "Active"!
  [chat setValue:[NSNumber numberWithBool:YES] forProperty:@"Account Joined" notify:NotifyNow];
  return [chat isGroupChat];
}

- (BOOL)groupChatsSupportTopic {
  return YES;
}

- (void)setTopic:(NSString *)topic forChat:(AIChat *)chat
{
    AILogWithSignature(@"setTopic:%@ forChat:%@", topic, chat);
    [chat setTopic:topic];
}

/*!
 * @brief A chat opened.
 *
 * If this is a group chat which belongs to us, aka a timeline chat, set it up how we want it.
 */
- (void)chatDidOpen:(NSNotification *)notification
{
	AIChat *chat = [notification object];
    AILogWithSignature(@"chatDidOpen: %@", chat);
	if(chat.isGroupChat && chat.account == self) {

        if (!chat.chatContainer.chatViewController.userListVisible) {
            [chat.chatContainer.chatViewController toggleUserList]; 
        }	
        [engine getRoomInformationFor:[chat.uniqueChatID integerValue]];
        AILogWithSignature(@"trying to join room : %@", chat.name);
        [engine joinRoom:[chat.identifier integerValue]];
    }
}


/*!
 * @brief Update the room chat
 * 
 * Remove the userlist
 */
- (void)updateCampfireChat:(AIChat *)campfireChat
{
  AILogWithSignature(@"chat room updated %@", campfireChat);
}

- (BOOL)sendMessageObject:(AIContentMessage *)inContentMessage
{
  NSString *roomName = inContentMessage.chat.name;
  [engine sendTextMessage:inContentMessage.encodedMessage toRoom:[roomName integerValue]];

  return YES;
}

- (void)setConnectionProgress:(NSNumber *)progress message:(NSString *)message
{
    //Why not sending out notifs?
	[self setValue:message forProperty:@"ConnectionProgressString" notify:NO];
	[self setValue:progress forProperty:@"ConnectionProgressPercent" notify:NO];	
	[self notifyOfChangedPropertiesSilently:NO];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark MSCampfireEngine delegate methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)didReceiveRooms:(NSDictionary *)rooms {
  
  AILogWithSignature(@"Got rooms %@ JSON value: %@", self, rooms);
  
  if (rooms) {
    updatedRoomsCount = 0;
    
    NSArray *roomArray = [rooms objectForKey:@"rooms"];
    
      if([roomArray count] > 0) {
          AIListGroup* campfireGroup = [adium.contactController groupWithUID:@"Campfire"];
          if(campfireGroup) {
              AILogWithSignature(@"found existing group for Campfire");
          } else {
              AILogWithSignature(@"null group?");
          }
      }
    for (NSDictionary *roomDictionary in roomArray) {
      NSNumber *roomId = [roomDictionary objectForKey:@"id"];
      NSString *roomName = [roomDictionary objectForKey:@"name"];
        
        AIChat *existingChat = [adium.chatController existingChatWithName:[roomId stringValue] onAccount:self];
        if (existingChat) {
            AILogWithSignature(@"There is already a room for #%@ - %@", roomId, roomName);
            [existingChat setDisplayName:roomName];
        } else {
            AILogWithSignature(@"Creating a room for %@", roomName);
            existingChat = [adium.chatController chatWithName:[roomId stringValue]
                                                   identifier:[roomId stringValue]
                                                    onAccount:self
                                             chatCreationInfo:roomDictionary];
            
            [existingChat setDisplayName:roomName];
        }
        existingChat.hideUserIconAndStatus = YES;
        AILogWithSignature(@"Bookmarking chat #%@ - %@", roomId, roomName);
        [adium.contactController bookmarkForChat:existingChat inGroup:[adium.contactController groupWithUID:@"Campfire"]];
    }
  } else {
    [self disconnect];
  }
 [self didConnect];
}

- (void)didReceiveRoomInformation:(NSDictionary *)roomDict
{ 
  NSDictionary *room = [roomDict objectForKey:@"room"];
  AILogWithSignature(@"Received information for room: %@", room);
  NSNumber *roomId = [room objectForKey:@"id"];
  AIChat *existingChat = [adium.chatController existingChatWithName:[roomId stringValue] onAccount:self];
  NSArray *users = [room objectForKey:@"users"];
  for (NSDictionary *userDict in users) {
      NSNumber *contactId = [userDict objectForKey:@"id"];
      if([contactId integerValue]!= authenticatedUserId) {
          AIListContact *contact = [[AIListContact alloc] initWithUID:[contactId stringValue]
                                                        account:self
                                                        service:[self service]];
          [contact setDisplayName:[userDict objectForKey:@"name"]];

          [existingChat setAlias:[userDict objectForKey:@"name"] forContact:contact];
          [existingChat addParticipatingListObject:contact notify:NotifyNow];    
          AILogWithSignature(@"Added contact: %@", contact);
          [engine getInformationForUser:[contactId intValue]];
      }
  }

}

- (void)didReceiveMessage:(NSDictionary *)message
{
  NSNumber *roomId = [message objectForKey:@"room_id"];
  AIChat *chat = [adium.chatController existingChatWithName:[roomId stringValue] onAccount:self];
  
  NSAttributedString *msg = [[NSAttributedString alloc] initWithString:[message objectForKey:@"body"]];
  
  AILogWithSignature(@"message = %@", message);
  
  if (!chat) {
    AILogWithSignature(@"chat with id %@ not found!", [message objectForKey:@"room_id"]);
    return;
  }
  
  NSString *messageType = [message objectForKey:@"type"];
  if ([messageType isEqualTo:@"TextMessage"] || [messageType isEqualTo:@"PasteMessage"]) {
    NSNumber *contactId = [message objectForKey:@"user_id"];
    AILogWithSignature(@"My ID=%ld, Sender ID=%@", authenticatedUserId, contactId);
    if( authenticatedUserId != [contactId integerValue] ) {
      AIContentMessage *contentMessage = [AIContentMessage messageInChat:chat
                                                              withSource:[self contactWithUID:[contactId stringValue]]
                                                             destination:self
                                                                    date:[NSDate date]
                                                                 message:msg
                                                               autoreply:NO];
      
      [adium.contentController receiveContentObject:contentMessage];    
    }
  } else if ([messageType isEqualTo:@"EnterMessage"]) {
      //TODO: make sure this isn't you
    NSNumber *contactId = [message objectForKey:@"user_id"];
      if(authenticatedUserId != [contactId intValue]) {
          [engine getInformationForUser:[contactId intValue]];
          [chat addParticipatingListObject:[self contactWithUID:[contactId stringValue]] notify:NotifyNow];
          [chat resortParticipants];
      }
  } else if ([messageType isEqualTo:@"UploadMessage"]) {
    // If this is an upload message, ask the engine to get the upload details
    NSNumber *uploadId = [message objectForKey:@"id"];
    NSNumber *roomId = [message objectForKey:@"room_id"];
    [engine getUploadForId:[uploadId integerValue] inRoom:[roomId integerValue]];
  } else if ([messageType isEqualTo:@"KickMessage"] || [messageType isEqualTo:@"LeaveMessage"]) {
      NSNumber *contactId = [message objectForKey:@"user_id"];
      [chat removeObject:[self contactWithUID:[contactId stringValue]]];   
      [chat resortParticipants];
  } else {
    NSLog(@"message = %@", message);
  } 
}

-(void)didReceiveInformationForUser:(NSDictionary *)user
{
    user = [user objectForKey:@"user"];
    AILogWithSignature(@"user = %@", user);
  //  AILogWithSignature(@"all keys %@", [user allKeys]);
    //AILogWithSignature(@"all values %@", [user allValues]);
    NSNumber *contactId = [user objectForKey:@"id"];
    // Create the request.
    NSURL* iconURL = [NSURL URLWithString:[user objectForKey:@"avatar_url"]];
    
    objc_setAssociatedObject(iconURL, &urlContact, contactId, OBJC_ASSOCIATION_RETAIN);
    
    NSURLRequest *theRequest = [NSURLRequest requestWithURL:iconURL
                                                cachePolicy:NSURLRequestUseProtocolCachePolicy
                                            timeoutInterval:60.0];
    
    
    // Create the connection with the request and start loading the data.
    NSURLDownload  *theDownload = [[NSURLDownload alloc] initWithRequest:theRequest
                                                                delegate:(id)self];
  //  if (theDownload) {
        // Set the destination file.
    NSString *localPath = [[NSString alloc] initWithFormat:@"/tmp/%@-avatar.png", contactId];
    [theDownload setDestination:localPath allowOverwrite:YES];

}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    // Release the connection.
    
    // Inform the user.
    AILogWithSignature(@"user icon download failed! Error - %@ %@",
          [error description],
          [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey]);
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    AILogWithSignature(@"download finished");

    NSURL* url = [[download request] URL];
    NSNumber* contactId = objc_getAssociatedObject(url, &urlContact);
    //I have no idea why this returns an array, but it does.
    AILogWithSignature(@"got avatar for contact %@", contactId);
    NSString *localPath = [[NSString alloc] initWithFormat:@"/tmp/%@-avatar.png", contactId];
    AILogWithSignature(@"loading avatar from %@", localPath);
    // Do something with the data.
    NSData *iconBinary = [NSData dataWithContentsOfFile:localPath];
    AILogWithSignature(@"bytes rx %ld", [iconBinary length] );
    //set icon on participant if present in all chats.
    AIListContact* needsIcon = [adium.contactController existingContactWithService:[self service] 
                                                                           account:self 
                                                                               UID:[contactId stringValue]];
//    AIChat *existingChat = [adium.chatController existingChatWithName:[roomId stringValue] onAccount:self];
//    NSSet* chatsParticipatingIn = [adium.chatController allGroupChatsContainingContact:(AIListContact *)inContact;
    [needsIcon setUserIconData:iconBinary];
    [needsIcon setServersideIconData:iconBinary notify:NotifyNow];

  //  [download release];
}



- (void)didReceiveInformationForAuthenticatedUser:(NSDictionary *)user
{
  NSString *authenticatedUserIdAsString = [[user objectForKey:@"user"] objectForKey:@"id"];
  authenticatedUserId = [authenticatedUserIdAsString integerValue];
  AILogWithSignature(@"Authenticated User ID = %ld", authenticatedUserId);
}

- (void)didReceiveUpload:(NSDictionary *)upload
{
  NSDictionary *data = [upload objectForKey:@"upload"];
  NSNumber *contactId = [data objectForKey:@"user_id"];
  NSAttributedString *msg = [[NSAttributedString alloc] initWithString:[data objectForKey:@"full_url"]];
  NSNumber *roomId = [data objectForKey:@"room_id"];
  AIChat *chat = [adium.chatController existingChatWithName:[roomId stringValue] onAccount:self];
  
  AIContentMessage *contentMessage = [AIContentMessage messageInChat:chat
                                                          withSource:[self contactWithUID:[contactId stringValue]]
                                                         destination:self
                                                                date:[NSDate date]
                                                             message:msg
                                                           autoreply:NO];
  
  [adium.contentController receiveContentObject:contentMessage]; 
}


@end

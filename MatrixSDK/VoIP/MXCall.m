/*
 Copyright 2015 OpenMarket Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXCall.h"

#import "MXSession.h"

@interface MXCall ()
{
    /**
     The manager of this object.
     */
    MXCallManager *callManager;

    /**
     The invite received by the peer
     */
    MXCallInviteEventContent *callInviteEventContent;
}

@end

@implementation MXCall

- (instancetype)initWithRoomId:(NSString *)roomId andCallManager:(MXCallManager *)callManager2
{
    self = [super init];
    if (self)
    {
        callManager = callManager2;

        _room = [callManager.mxSession roomWithRoomId:roomId];

        _callId = [[NSUUID UUID] UUIDString];
        _callerId = callManager.mxSession.myUser.userId;

        _state = MXCallStateFledgling;
    }
    return self;
}

- (void)handleCallEvent:(MXEvent *)event
{
    switch (event.eventType)
    {
        case MXEventTypeCallInvite:
        {
            callInviteEventContent = [MXCallInviteEventContent modelFromJSON:event.content];

            _callId = callInviteEventContent.callId;
            _callerId = event.userId;
            _isIncoming = YES;

            self.state = MXCallStateRinging;
            break;
        }

        case MXEventTypeCallAnswer:
        {
            // MXCall receives this event only when it placed a call
            MXCallAnswerEventContent *content = [MXCallAnswerEventContent modelFromJSON:event.content];

            // Let's the stack finalise the connection
            [callManager.callStack handleAnswer:content.answer.sdp success:^{

                // Call is up
                self.state = MXCallStateConnected;

            } failure:^(NSError *error) {
                // @TODO
            }];
            break;
        }

        case MXEventTypeCallHangup:
        {
            if (_state != MXCallStateEnded)
            {
                // Terminate the call at the stack level
                [callManager.callStack terminate];

                self.state = MXCallStateEnded;
            }
        }

        default:
            break;
    }
}


#pragma mark - Controls
- (void)callWithVideo:(BOOL)video
{
    _isIncoming = NO;

    self.state = MXCallStateWaitLocalMedia;

    [callManager.callStack startCapturingMediaWithVideo:video success:^() {

        [callManager.callStack createOffer:^(NSString *sdp) {

            self.state = MXCallStateCreateOffer;

            NSLog(@"[MXCallManager] placeCallInRoom. Offer created: %@", sdp);

            // The call invite can sent to the HS
            NSDictionary *content = @{
                                      @"call_id": _callId,
                                      @"offer": @{
                                              @"type": @"offer",
                                              @"sdp": sdp
                                              },
                                      @"version": @(0),
                                      @"lifetime": @(30 * 1000)
                                      };
            [_room sendEventOfType:kMXEventTypeStringCallInvite content:content success:^(NSString *eventId) {

                self.state = MXCallStateInviteSent;

            } failure:^(NSError *error) {
                // @TODO
            }];

        } failure:^(NSError *error) {
            // @TODO
        }];
    } failure:^(NSError *error) {
        // @TODO
    }];
}

- (void)answer
{
    if (self.state == MXCallStateRinging)
    {
        self.state = MXCallStateWaitLocalMedia;

        [callManager.callStack startCapturingMediaWithVideo:self.isVideoCall success:^{

            // Create a sdp answer from the offer we got
            self.state = MXCallStateCreateAnswer;
            self.state = MXCallStateConnecting;
            [callManager.callStack handleOffer:callInviteEventContent.offer.sdp success:^(NSString *sdpAnswer) {

                // The call invite can sent to the HS
                NSDictionary *content = @{
                                          @"call_id": _callId,
                                          @"answer": @{
                                                  @"type": @"answer",
                                                  @"sdp": sdpAnswer
                                                  },
                                          @"version": @(0),
                                          };
                [_room sendEventOfType:kMXEventTypeStringCallAnswer content:content success:^(NSString *eventId) {

                    self.state = MXCallStateConnected;

                } failure:^(NSError *error) {
                    // @TODO
                }];
                
            } failure:^(NSError *error) {
                // @TODO
            }];
            
            callInviteEventContent = nil;

        } failure:^(NSError *error) {
            // @TODO
        }];
    }
}

- (void)hangup
{
    if (self.state != MXCallStateEnded)
    {
        // Terminate the call at the stack level
        [callManager.callStack terminate];

        // Send the hangup event
        NSDictionary *content = @{
                                  @"call_id": _callId,
                                  @"version": @(0)
                                  };
        [_room sendEventOfType:kMXEventTypeStringCallHangup content:content success:nil failure:^(NSError *error) {
            // @TODO
        }];
        
        self.state = MXCallStateEnded;
    }
}


#pragma marl - Properties
- (BOOL)isVideoCall
{
    // @TODO
    return NO;
}

- (void)setState:(MXCallState)state
{
    _state = state;

    // @TODO: Notify change
}

#pragma mark - Private methods
- (void)sendHangupEvent
{

}

@end
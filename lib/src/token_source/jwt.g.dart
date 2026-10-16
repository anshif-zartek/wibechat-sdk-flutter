// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jwt.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WibeChatVideoGrant _$WibeChatVideoGrantFromJson(Map<String, dynamic> json) => WibeChatVideoGrant(
  room: json['room'] as String?,
  roomCreate: json['roomCreate'] as bool?,
  roomJoin: json['roomJoin'] as bool?,
  roomList: json['roomList'] as bool?,
  roomRecord: json['roomRecord'] as bool?,
  roomAdmin: json['roomAdmin'] as bool?,
  canPublish: json['canPublish'] as bool?,
  canSubscribe: json['canSubscribe'] as bool?,
  canPublishData: json['canPublishData'] as bool?,
  canPublishSources: (json['canPublishSources'] as List<dynamic>?)?.map((e) => e as String).toList(),
  hidden: json['hidden'] as bool?,
  recorder: json['recorder'] as bool?,
);

Map<String, dynamic> _$WibeChatVideoGrantToJson(WibeChatVideoGrant instance) => <String, dynamic>{
  'room': ?instance.room,
  'roomCreate': ?instance.roomCreate,
  'roomJoin': ?instance.roomJoin,
  'roomList': ?instance.roomList,
  'roomRecord': ?instance.roomRecord,
  'roomAdmin': ?instance.roomAdmin,
  'canPublish': ?instance.canPublish,
  'canSubscribe': ?instance.canSubscribe,
  'canPublishData': ?instance.canPublishData,
  'canPublishSources': ?instance.canPublishSources,
  'hidden': ?instance.hidden,
  'recorder': ?instance.recorder,
};

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/providers.dart';
import '../application/extensions.dart';
import '../domain/extensions.dart';

class SeedPacketPhotoSlot extends ConsumerWidget {
  const SeedPacketPhotoSlot({super.key,required this.side,required this.onCapture,required this.onRemove,this.draft,this.photoId,this.busy=false});
  final String side;final CapturedPhoto? draft;final String? photoId;final bool busy;
  final void Function(bool camera) onCapture;final VoidCallback onRemove;
  @override Widget build(BuildContext context,WidgetRef ref) {
    final records=ref.watch(recordsProvider(RecordKind.photo));
    final saved=records.asData?.value.where((p)=>p['id']==photoId).firstOrNull;
    final thumb=draft?.thumbnail ?? (saved==null?null:base64Decode(saved['thumbnail'] as String));
    return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('Seed packet — $side',style:Theme.of(context).textTheme.titleMedium),
      if(thumb!=null)InkWell(onTap:()=>showDialog<void>(context:context,builder:(c)=>Dialog(child:Padding(padding:const EdgeInsets.all(12),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Flexible(child:FutureBuilder<Uint8List>(future:draft!=null?Future.value(draft!.image):saved!['image'] is String?Future.value(base64Decode(saved['image'] as String)):
          ref.read(photoRepositoryProvider).read(saved['storagePath'] as String),builder:(_,s)=>s.hasData?Image.memory(s.data!,fit:BoxFit.contain):s.hasError?const Text('Full photo unavailable. The saved thumbnail remains available offline.'):const CircularProgressIndicator())),
        TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Close')),
      ])))) ,child:Image.memory(thumb,height:100,fit:BoxFit.contain,errorBuilder:(_,_,_)=>const Icon(Icons.image_not_supported))),
      if(thumb==null)Text(photoId==null?'No $side photo':'Photo loading or unavailable'),
      Wrap(spacing:8,children:[
        TextButton.icon(onPressed:busy?null:()=>onCapture(true),icon:const Icon(Icons.camera_alt_outlined),label:Text('Take $side photo')),
        TextButton(onPressed:busy?null:()=>onCapture(false),child:Text('Choose $side photo')),
        if(thumb!=null || photoId!=null)TextButton(onPressed:busy?null:onRemove,child:Text('Remove $side photo')),
      ]),
    ])));
  }
}

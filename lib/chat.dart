import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:my_chatapp_2021/widget/full_photo.dart';
import 'package:my_chatapp_2021/widget/loading.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;


import 'const.dart';

class Chat extends StatelessWidget {
  final String peerId;
  final String peerAvatar;
  final String peerName;
  final String peerPushToken;

  Chat({Key? key, required this.peerId, required this.peerAvatar, required this.peerName, required this.peerPushToken}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios, color: deepPurple),
        ),
        iconTheme: IconThemeData(
          color: Colors.white, //change your color here
        ),
        centerTitle: false,
        backgroundColor: white,
        elevation: 2,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Row(
              children: [
                Material(
                  child: peerAvatar != null? peerAvatar != ''?
                  CachedNetworkImage(
                    placeholder: (context, url) =>
                        Container(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor:
                            AlwaysStoppedAnimation<Color>(deepPurple),
                          ),
                          width: 45.0,
                          height: 45.0,
                          padding: EdgeInsets.all(8.0),
                        ),
                    // imageUrl: peerAvatar,
                    imageUrl: peerAvatar,
                    width: 45.0,
                    height: 45.0,
                    fit: BoxFit.cover,
                  )
                      : Icon(
                    Icons.account_circle,
                    size: 43.0,
                    color: deepPurple,
                  ):Icon(
                    Icons.account_circle,
                    size: 43.0,
                    color: deepPurple,
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(23.0)),
                  clipBehavior: Clip.hardEdge,
                ),
              ],

            ),
            Expanded(
              child: Container(
                margin: EdgeInsets.only(left: 10),
                child: Text(
                  "${peerName}",overflow: TextOverflow.ellipsis,maxLines: 1,
                  style: TextStyle(
                    color: deepPurple, fontWeight: FontWeight.w600,fontSize: 16,),
                ),
              ),
            ),
          ],
        ),
      ),
      body: ChatScreen(
        peerId: peerId,
        peerAvatar: peerAvatar,
        peerName: peerName,
        peerPushToken : peerPushToken,
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerAvatar;
  final String peerName;
  final String peerPushToken;

  ChatScreen({Key? key, required this.peerId, required this.peerAvatar, required this.peerName, required this.peerPushToken}) : super(key: key);

  @override
  State createState() => ChatScreenState(peerId: peerId, peerAvatar: peerAvatar, peerName: peerName, peerPushToken: peerPushToken);
}

class ChatScreenState extends State<ChatScreen> {
  ChatScreenState({Key? key, required this.peerId, required this.peerAvatar, required this.peerName, required this.peerPushToken});

  String peerId;
  String peerAvatar;
  String peerName;
  String peerPushToken;
  String? id;

  List<QueryDocumentSnapshot> listMessage = new List.from([]);
  int _limit = 20;
  int _limitIncrement = 20;
  String groupChatId = "";
  SharedPreferences? prefs;

  File? imageFile;
  bool isLoading = false;
  bool isShowSticker = false;
  String imageUrl = "";

  final TextEditingController textEditingController = TextEditingController();
  final ScrollController listScrollController = ScrollController();
  final FocusNode focusNode = FocusNode();

  _scrollListener() {
    if (listScrollController.offset >= listScrollController.position.maxScrollExtent &&
        !listScrollController.position.outOfRange) {
      setState(() {
        _limit += _limitIncrement;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    focusNode.addListener(onFocusChange);
    listScrollController.addListener(_scrollListener);
    readLocal();
  }

  void onFocusChange() {
    if (focusNode.hasFocus) {
      // Hide sticker when keyboard appear
      setState(() {
        isShowSticker = false;
      });
    }
  }

  readLocal() async {
    prefs = await SharedPreferences.getInstance();
    id = prefs?.getString('id') ?? '';
    if (id.hashCode <= peerId.hashCode) {
      groupChatId = '$id-$peerId';
    } else {
      groupChatId = '$peerId-$id';
    }

    FirebaseFirestore.instance.collection('users').doc(id).update({'chattingWith': peerId});

    setState(() {});
  }

  Future getImage() async {
    ImagePicker imagePicker = ImagePicker();
    PickedFile? pickedFile;

    pickedFile = await imagePicker.getImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      imageFile = File(pickedFile.path);
      if (imageFile != null) {
        setState(() {
          isLoading = true;
        });
        uploadFile();
      }
    }
  }

  void getSticker() {
    // Hide keyboard when sticker appear
    focusNode.unfocus();
    setState(() {
      isShowSticker = !isShowSticker;
    });
  }

  Future uploadFile() async {
    String fileName = DateTime.now().millisecondsSinceEpoch.toString();
    Reference reference = FirebaseStorage.instance.ref().child(fileName);
    UploadTask uploadTask = reference.putFile(imageFile!);

    try {
      TaskSnapshot snapshot = await uploadTask;
      imageUrl = await snapshot.ref.getDownloadURL();
      setState(() {
        isLoading = false;
        onSendMessage(imageUrl, 1);
      });
    } on FirebaseException catch (e) {
      setState(() {
        isLoading = false;
      });
      Fluttertoast.showToast(msg: e.message ?? e.toString());
    }
  }

  void onSendMessage(String content, int type) {
    // type: 0 = text, 1 = image, 2 = sticker
    if (content.trim() != '') {
      textEditingController.clear();

      var documentReference = FirebaseFirestore.instance
          .collection('messages')
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(DateTime.now().millisecondsSinceEpoch.toString());

      FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.set(
          documentReference,
          {
            'idFrom': id,
            'idTo': peerId,
            'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
            'content': content,
            'type': type
          },
        );
      });
      //For notification
      callOnFcmApiSendPushNotifications(peerPushToken);

      // const url2 = 'https://fcm.googleapis.com/fcm/send';
      // var url2 = Uri.parse("https://fcm.googleapis.com/fcm/send");
      // var headers = {'Content-Type': 'application/json',
      //   'Authorization':'AAAAZYp1ruA:APA91bFpQ5movjnquLNcoXX-ng8gj7GfkMgbNESn42yeSxmSBhcVsY_DTkCnhOlxxRx-P-T7LGUPERsotEfrhBE1jA1gzl4Jtg1NcbAtV_sOOMWEpLPgPfs_nK81m-ocvsK3lPzozYMa'};
      // const payload = { "notification": {
      //   "title": "Test Notification",
      //   "text": "Refer by Aman Shaikh"
      // },
      //   "to" : peerPushToken,
      // } ;
      // var response = await http.post(url2,headers:headers, body: jsonEncode(payload));
      // print(response.statusCode);



      listScrollController.animateTo(0.0, duration: Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      Fluttertoast.showToast(msg: 'Nothing to send', backgroundColor: deepPurple, textColor: white);
    }
  }

  Widget buildItem(int index, DocumentSnapshot? document) {
    if (document != null) {
      if (document.get('idFrom') == id) {
        // Right (my message)
        return Row(
          children: <Widget>[
            document.get('type') == 0
                // Text
                ? Container(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: EdgeInsets.only(bottom: 5.0),
                          child: Text(
                            document.get('content'),
                            style: TextStyle(color: primaryColor),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              child: Text(
                                DateFormat('dd MMM  hh:mm a').format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                        int.parse(document.get('timestamp')))),
                                style: TextStyle(
                                  color: lightBlack,
                                  fontSize: 9.0,
                                ),
                              ),
                              margin: EdgeInsets.only(left: 100.0),
                            ),
                          ],
                        )
                      ],
                    ),
                    padding: EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                    width: 200.0,
                    decoration: BoxDecoration(color: greyColor2,  borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(0), bottomLeft:Radius.circular(10), bottomRight:Radius.circular(10))),
                    margin: EdgeInsets.only(bottom: isLastMessageRight(index) ? 5.0 : 5.0, right: 10.0),
                  )
                : document.get('type') == 1
                    // Image
                    ? Container(
                        child: OutlinedButton(
                          child: Material(
                            child: Stack(
                              children: [
                                Image.network(
                                  document.get("content"),
                                  loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: greyColor2,
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(8.0),
                                        ),
                                      ),
                                      width: 200.0,
                                      height: 200.0,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: greyColor2,
                                          value: loadingProgress.expectedTotalBytes != null &&
                                              loadingProgress.expectedTotalBytes != null
                                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, object, stackTrace) {
                                    return Material(
                                      child: Image.asset(
                                        'images/img_not_available.jpeg',
                                        width: 200.0,
                                        height: 200.0,
                                        fit: BoxFit.cover,
                                      ),
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(8.0),
                                      ),
                                      clipBehavior: Clip.hardEdge,
                                    );
                                  },
                                  width: 200.0,
                                  height: 200.0,
                                  fit: BoxFit.cover,
                                ),

                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  width: 90,
                                  height: 20,
                                  // Note: without ClipRect, the blur region will be expanded to full
                                  // size of the Image instead of custom size
                                  child: ClipRect(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
                                      child: Container(
                                        color: Colors.black.withOpacity(0.0),
                                      ),
                                    ),
                                  ),
                                ),

                                Container(
                                  width: 190,
                                  height: 195,
                                  child: Align(
                                    alignment: Alignment.bottomRight,
                                      child: Text(
                                        DateFormat('dd MMM  hh:mm a').format(
                                            DateTime.fromMillisecondsSinceEpoch(
                                                int.parse(document.get('timestamp')))),
                                        style: TextStyle(
                                          color: black,
                                          fontSize: 10.0,
                                          fontWeight: FontWeight.w900
                                        ),
                                      ),
                                  ),
                                ),

                              ],

                            ),
                            borderRadius: BorderRadius.all(Radius.circular(8.0)),
                            clipBehavior: Clip.hardEdge,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => FullPhoto(
                                  url: document.get('content'),
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.all(5),
                            primary: Colors.white,
                            backgroundColor: greyColor,
                            elevation: 5,
                            side: BorderSide(color: greyColor, width: 3),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(0),
                                bottomLeft:Radius.circular(12),
                                bottomRight:Radius.circular(12)
                            )),
                          ),
                        ),
                        margin: EdgeInsets.only(bottom: isLastMessageRight(index) ? 5.0 : 5.0, right: 10.0),
                      )
                    // Sticker
                    : Container(
                        child: Column(
                          children: [
                            Image.asset(
                              'images/${document.get('content')}.gif',
                              width: 100.0,
                              height: 100.0,
                              fit: BoxFit.cover,
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  child: Text(
                                    DateFormat('dd MMM  hh:mm a').format(
                                        DateTime.fromMillisecondsSinceEpoch(
                                            int.parse(document.get('timestamp')))),
                                    style: TextStyle(
                                      color: lightBlack,
                                      fontSize: 9.0,
                                    ),
                                  ),
                                  margin: EdgeInsets.only(right: 10),
                                ),
                              ],
                            )
                          ],
                        ),
                        margin: EdgeInsets.only(bottom: isLastMessageRight(index) ? 20.0 : 10.0, right: 10.0),
                      ),
          ],
          mainAxisAlignment: MainAxisAlignment.end,
        );
      } else {
        // Left (peer message)
        return Container(
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  isLastMessageLeft(index)
                      ? Material(
                          child: Image.network(
                            peerAvatar,
                            loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  color: deepPurple,
                                  value: loadingProgress.expectedTotalBytes != null &&
                                          loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                            errorBuilder: (context, object, stackTrace) {
                              return Icon(
                                Icons.account_circle,
                                size: 35,
                                color: greyColor,
                              );
                            },
                            width: 35,
                            height: 35,
                            fit: BoxFit.cover,
                          ),
                          borderRadius: BorderRadius.all(
                            Radius.circular(18.0),
                          ),
                          clipBehavior: Clip.hardEdge,
                        )
                      : Container(width: 35.0),
                  document.get('type') == 0
                  // Text
                      ? Container(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: EdgeInsets.only(bottom: 5.0),
                          child: Text(
                            document.get('content'),
                            style: TextStyle(color: white),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              child: Text(
                                DateFormat('dd MMM  hh:mm a').format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                        int.parse(document.get('timestamp')))),
                                style: TextStyle(
                                  color: greyColor,
                                  fontSize: 9.0,
                                ),
                              ),
                              margin: EdgeInsets.only(left: 100.0),
                            ),
                          ],
                        )
                      ],
                    ),
                    padding: EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                    width: 200.0,
                    decoration: BoxDecoration(color: deepPurple,  borderRadius: BorderRadius.only(topLeft: Radius.circular(0), topRight: Radius.circular(20), bottomLeft:Radius.circular(10), bottomRight:Radius.circular(10))),
                    margin: EdgeInsets.only(bottom: isLastMessageRight(index) ? 5.0 : 5.0, right: 10.0),
                  )
                      : document.get('type') == 1
                  // Image
                      ? Container(
                    child: OutlinedButton(
                      child: Material(
                        child: Stack(
                          children: [
                            Image.network(
                              document.get("content"),
                              loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: greyColor2,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(8.0),
                                    ),
                                  ),
                                  width: 200.0,
                                  height: 200.0,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: deepPurple,
                                      value: loadingProgress.expectedTotalBytes != null &&
                                          loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, object, stackTrace) {
                                return Material(
                                  child: Image.asset(
                                    'images/img_not_available.jpeg',
                                    width: 200.0,
                                    height: 200.0,
                                    fit: BoxFit.cover,
                                  ),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(8.0),
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                );
                              },
                              width: 200.0,
                              height: 200.0,
                              fit: BoxFit.cover,
                            ),

                            Positioned(
                              bottom: 0,
                              right: 0,
                              width: 90,
                              height: 20,
                              // Note: without ClipRect, the blur region will be expanded to full
                              // size of the Image instead of custom size
                              child: ClipRect(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
                                  child: Container(
                                    color: Colors.black.withOpacity(0.0),
                                  ),
                                ),
                              ),
                            ),

                            Container(
                              width: 190,
                              height: 195,
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: Text(
                                  DateFormat('dd MMM  hh:mm a').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                          int.parse(document.get('timestamp')))),
                                  style: TextStyle(
                                      color: black,
                                      fontSize: 10.0,
                                      fontWeight: FontWeight.w900
                                  ),
                                ),
                              ),
                            ),

                          ],

                        ),
                        borderRadius: BorderRadius.all(Radius.circular(8.0)),
                        clipBehavior: Clip.hardEdge,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FullPhoto(
                              url: document.get('content'),
                            ),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.all(5),
                        primary: Colors.white,
                        backgroundColor: deepPurple,
                        elevation: 5,
                        side: BorderSide(color: deepPurple, width: 3),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(0),
                            topRight: Radius.circular(12),
                            bottomLeft:Radius.circular(12),
                            bottomRight:Radius.circular(12)
                        )),
                      ),
                    ),
                    margin: EdgeInsets.only(bottom: isLastMessageRight(index) ? 5.0 : 5.0, right: 10.0),
                  )
                  // Sticker
                      : Container(
                    child: Column(
                      children: [
                        Image.asset(
                          'images/${document.get('content')}.gif',
                          width: 100.0,
                          height: 100.0,
                          fit: BoxFit.cover,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              child: Text(
                                DateFormat('dd MMM  hh:mm a').format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                        int.parse(document.get('timestamp')))),
                                style: TextStyle(
                                  color: lightBlack,
                                  fontSize: 9.0,
                                ),
                              ),
                              margin: EdgeInsets.only(right: 10),
                            ),
                          ],
                        )
                      ],
                    ),
                    margin: EdgeInsets.only(bottom: isLastMessageRight(index) ? 20.0 : 10.0, right: 10.0),
                  ),
                ],
              ),

              // Time
              isLastMessageLeft(index)
                  ? Container(
                      child: Text(
                        DateFormat('dd MMM yyyy')
                            .format(DateTime.fromMillisecondsSinceEpoch(int.parse(document.get('timestamp')))),
                        style: TextStyle(color: greyColor, fontSize: 12.0,),
                      ),
                      margin: EdgeInsets.only(left: 50.0, top: 5.0, bottom: 5.0),
                    )
                  : Container()
            ],
            crossAxisAlignment: CrossAxisAlignment.start,
          ),
          margin: EdgeInsets.only(bottom: 10.0),
        );
      }
    } else {
      return SizedBox.shrink();
    }
  }

  bool isLastMessageLeft(int index) {
    if ((index > 0 && listMessage[index - 1].get('idFrom') == id) || index == 0) {
      return true;
    } else {
      return false;
    }
  }

  bool isLastMessageRight(int index) {
    if ((index > 0 && listMessage[index - 1].get('idFrom') != id) || index == 0) {
      return true;
    } else {
      return false;
    }
  }

  Future<bool> onBackPress() {
    if (isShowSticker) {
      setState(() {
        isShowSticker = false;
      });
    } else {
      FirebaseFirestore.instance.collection('users').doc(id).update({'chattingWith': null});
      Navigator.pop(context);
    }

    return Future.value(false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              // List of messages
              buildListMessage(),

              // Sticker
              isShowSticker ? buildSticker() : Container(),

              // Input content
              buildInput(),
            ],
          ),

          // Loading
          buildLoading()
        ],
      ),
      onWillPop: onBackPress,
    );
  }

  Widget buildSticker() {
    return Expanded(
      child: Container(
            child : Row(
              children: <Widget>[
                TextButton(
                  onPressed: () => onSendMessage('mimi1', 2),
                  child: Image.asset(
                    'images/mimi1.gif',
                    width: 50.0,
                    height: 50.0,
                    fit: BoxFit.cover,
                  ),
                ),
                TextButton(
                  onPressed: () => onSendMessage('mimi2', 2),
                  child: Image.asset(
                    'images/mimi2.gif',
                    width: 50.0,
                    height: 50.0,
                    fit: BoxFit.cover,
                  ),
                ),
                TextButton(
                  onPressed: () => onSendMessage('mimi3', 2),
                  child: Image.asset(
                    'images/mimi3.gif',
                    width: 50.0,
                    height: 50.0,
                    fit: BoxFit.cover,
                  ),
                )
              ],
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            ),

        decoration: BoxDecoration(border: Border(top: BorderSide(color: greyColor2, width: 0.5)), color: Colors.white),
        padding: EdgeInsets.all(5.0),
        height: 60.0,
      ),

    );
  }

  Widget buildLoading() {
    return Positioned(
      child: isLoading ? const Loading() : Container(),
    );
  }

  Widget buildInput() {
    return Container(
      child: Row(
        children: <Widget>[
          // Button send image
          Material(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 1.0),
              child: IconButton(
                icon: Icon(Icons.image),
                onPressed: getImage,
                color: deepPurple,
              ),
            ),
            color: Colors.white,
          ),
          Material(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 1.0),
              child: IconButton(
                icon: Icon(Icons.face),
                onPressed: getSticker,
                color: deepPurple,
              ),
            ),
            color: Colors.white,
          ),

          // Edit text
          Flexible(
            child: Container(
              child: TextField(
                onSubmitted: (value) {
                  onSendMessage(textEditingController.text, 0);
                },
                style: TextStyle(color: primaryColor, fontSize: 15.0),
                controller: textEditingController,
                decoration: InputDecoration.collapsed(
                  hintText: 'Type your message...',
                  hintStyle: TextStyle(color: greyColor),
                ),
                focusNode: focusNode,
              ),
            ),
          ),

          // Button send message
          Material(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8.0),
              child: IconButton(
                icon: Icon(Icons.send),
                onPressed: () => onSendMessage(textEditingController.text, 0),
                color: deepPurple,
              ),
            ),
            color: Colors.white,
          ),
        ],
      ),
      width: double.infinity,
      height: 50.0,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: greyColor2, width: 0.5)), color: Colors.white),
    );
  }

  Widget buildListMessage() {
    return Flexible(
      child: groupChatId.isNotEmpty
          ? StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('messages')
                  .doc(groupChatId)
                  .collection(groupChatId)
                  .orderBy('timestamp', descending: true)
                  .limit(_limit)
                  .snapshots(),
              builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.hasData) {
                  listMessage.addAll(snapshot.data!.docs);
                  return ListView.builder(
                    padding: EdgeInsets.all(10.0),
                    itemBuilder: (context, index) => buildItem(index, snapshot.data?.docs[index]),
                    itemCount: snapshot.data?.docs.length,
                    reverse: true,
                    controller: listScrollController,
                  );
                } else {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(deepPurple),
                    ),
                  );
                }
              },
            )
          : Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(deepPurple),
              ),
            ),
    );
  }
}

//For Notification

Future<bool> callOnFcmApiSendPushNotifications(String userToken) async {


  // var postUrl = 'https://fcm.googleapis.com/fcm/send';
  var postUrl = Uri.parse("https://fcm.googleapis.com/fcm/send");
  final data = {
    "registration_ids" : userToken,
    "collapse_key" : "type_a",
    "notification" : {
      "title": 'NewTextTitle',
      "body" : 'NewTextBody',
    }
  };

  final headers = {
    'content-type': 'application/json',
    'Authorization': 'AAAAZYp1ruA:APA91bFpQ5movjnquLNcoXX-ng8gj7GfkMgbNESn42yeSxmSBhcVsY_DTkCnhOlxxRx-P-T7LGUPERsotEfrhBE1jA1gzl4Jtg1NcbAtV_sOOMWEpLPgPfs_nK81m-ocvsK3lPzozYMa' // 'key=YOUR_SERVER_KEY'
  };

  final response = await http.post(
      postUrl,
      body: json.encode(data),
      encoding: Encoding.getByName('utf-8'),
      headers: headers);

  if (response.statusCode == 200) {
    // on success do sth
    print('test ok push CFM');
    return true;
  } else {
    print(' CFM error');
    print(postUrl);
    // on failure do sth
    return false;
  }
}
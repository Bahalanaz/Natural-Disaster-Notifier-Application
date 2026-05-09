import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FriendList extends StatefulWidget {
  const FriendList({super.key});

  @override
  State<FriendList> createState() => _FriendListState();
}

class _FriendListState extends State<FriendList> {
  TextEditingController searchController = TextEditingController();
  String searchText = "";

  final currentUser = FirebaseAuth.instance.currentUser;

  //  Send Friend Request 
  bool _sendingRequest = false;

  void sendFriendRequest(String targetUserId) async {
    if (_sendingRequest || currentUser == null) return;
    _sendingRequest = true;

    try {
      // Check if a request already exists in either direction
      final existing = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('from', isEqualTo: currentUser!.uid)
          .where('to', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existing.docs.isNotEmpty) return; // already sent

      // Check if they already sent us a request — auto-accept instead
      final reverse = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('from', isEqualTo: targetUserId)
          .where('to', isEqualTo: currentUser!.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (reverse.docs.isNotEmpty) {
        // They already sent us a request — accept it
        await acceptRequest(reverse.docs.first.id, targetUserId);
        return;
      }

      await FirebaseFirestore.instance.collection('friend_requests').add({
        'from': currentUser!.uid,
        'to': targetUserId,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } finally {
      _sendingRequest = false;
    }
  }

  //  Accept Request
  Future<void> acceptRequest(String requestId, String fromUserId) async {
    if (currentUser == null) return;
    await FirebaseFirestore.instance
        .collection('friends')
        .doc(currentUser!.uid)
        .set({
      'connections': FieldValue.arrayUnion([fromUserId])
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection('friends')
        .doc(fromUserId)
        .set({
      'connections': FieldValue.arrayUnion([currentUser!.uid])
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection('friend_requests')
        .doc(requestId)
        .update({'status': 'accepted'});
  }

  //  Deny Request
  void denyRequest(String requestId) async {
    await FirebaseFirestore.instance
        .collection('friend_requests')
        .doc(requestId)
        .update({'status': 'denied'});
  }

  // Remove a friend (used for deleted accounts or unfriending)
  void _removeFriend(String targetUserId) async {
    if (currentUser == null) return;
    // Remove from my connections
    await FirebaseFirestore.instance
        .collection('friends')
        .doc(currentUser!.uid)
        .update({
      'connections': FieldValue.arrayRemove([targetUserId])
    });

    // Remove me from their connections (if their doc still exists)
    try {
      await FirebaseFirestore.instance
          .collection('friends')
          .doc(targetUserId)
          .update({
        'connections': FieldValue.arrayRemove([currentUser!.uid])
      });
    } catch (_) {
      // Their friends doc might not exist anymore
    }
  }

  //  Smart Button (Add / Pending / Friends)
  Widget buildButton(String targetUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friend_requests')
          .where('from', isEqualTo: currentUser?.uid)
          .where('to', isEqualTo: targetUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        if (snapshot.data!.docs.isNotEmpty) {
          var request = snapshot.data!.docs.first;
          if (request['status'] == 'pending') {
            return const Text("Pending",
                style: TextStyle(color: Colors.orange));
          }
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('friends')
              .doc(currentUser?.uid)
              .snapshots(),
          builder: (context, friendSnapshot) {
            if (friendSnapshot.hasData && friendSnapshot.data!.exists) {
              List connections = friendSnapshot.data!['connections'] ?? [];
              if (connections.contains(targetUserId)) {
                return const Text("Friends",
                    style: TextStyle(color: Colors.green));
              }
            }

            return ElevatedButton(
              onPressed: () {
                sendFriendRequest(targetUserId);
              },
              child: const Text("Add"),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Connections"),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: "Search"),
              Tab(text: "Requests"),
              Tab(text: "Friends"),
            ],
          ),
        ),
        body: Column(
          children: [
            // 🔍 Search Bar
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: searchController,
                onChanged: (value) {
                  setState(() {
                    searchText = value.trim().toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: "Search",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),

            Expanded(
              child: TabBarView(
                children: [
                  // 🔹 SEARCH TAB
                 // 🔹 SEARCH TAB
                  searchText.isEmpty
                      ? const Center(child: Text("Search users by username"))
                      : StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              // 🔹 PREFIX SEARCH (works with lowercase field)
                              .orderBy('usernameLower')
                              .startAt([searchText])
                              .endAt([searchText + '\uf8ff'])
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            var users = snapshot.data!.docs;
                            if (users.isEmpty) {
                              return const Center(child: Text("No user found"));
                            }

                            return ListView.builder(
                              itemCount: users.length,
                              itemBuilder: (context, index) {
                                var user = users[index];

                                if (user.id == currentUser?.uid) return const SizedBox();

                                return ListTile(
                                  leading: const CircleAvatar(),
                                  title: Text(user['username']),
                                  subtitle: Text(user['email']),
                                  trailing: buildButton(user.id),
                                );
                              },
                            );
                          },
                        ),

                  // 🔹 REQUESTS TAB
                  StreamBuilder(
                    stream: FirebaseFirestore.instance
                        .collection('friend_requests')
                        .where('to', isEqualTo: currentUser?.uid)
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }

                      var requests = snapshot.data!.docs;
                      if (requests.isEmpty) {
                        return const Center(child: Text("No requests"));
                      }

                      return ListView.builder(
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          var req = requests[index];

                          return FutureBuilder(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .doc(req['from'])
                                .get(),
                            builder: (context, userSnapshot) {
                              if (!userSnapshot.hasData) {
                                return const ListTile(
                                    title: Text("Loading..."));
                              }

                              var userData = userSnapshot.data!;

                              // Handle deleted user who sent the request
                              if (!userData.exists) {
                                // Auto-clean the stale request
                                denyRequest(req.id);
                                return const SizedBox();
                              }

                              final data = userData.data() as Map<String, dynamic>? ?? {};

                              return ListTile(
                                leading: const CircleAvatar(),
                                title: Text(data['username'] ?? 'Unknown'),
                                subtitle: Text(data['email'] ?? ''),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check,
                                          color: Colors.green),
                                      onPressed: () {
                                        acceptRequest(req.id, req['from']);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.red),
                                      onPressed: () {
                                        denyRequest(req.id);
                                      },
                                    ),
                                  ],
                                ),
                              ); 
                            },
                          );
                        },
                      );
                    },
                  ),

                  // 🔹 FRIENDS TAB — shows live safety status
                  StreamBuilder(
                    stream: FirebaseFirestore.instance
                        .collection('friends')
                        .doc(currentUser?.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return const Center(child: Text("No friends yet"));
                      }

                      List friends = snapshot.data!['connections'] ?? [];
                      if (friends.isEmpty) {
                        return const Center(child: Text("No friends yet"));
                      }

                      return ListView.builder(
                        itemCount: friends.length,
                        itemBuilder: (context, index) {
                          // Use StreamBuilder for real-time status updates
                          return StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(friends[index])
                                .snapshots(),
                            builder: (context, userSnapshot) {
                              if (!userSnapshot.hasData) {
                                return const ListTile(
                                    title: Text("Loading..."));
                              }

                              // Handle deleted user — auto-remove from friends list
                              if (!userSnapshot.data!.exists) {
                                // Schedule removal after build completes to avoid setState-during-build
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _removeFriend(friends[index]);
                                });
                                return const SizedBox();
                              }

                              var userData = userSnapshot.data!;
                              final data = userData.data() as Map<String, dynamic>? ?? {};
                              bool isSafe = data.containsKey('isSafe') ? data['isSafe'] : true;
                              Timestamp? lastUpdate = data.containsKey('lastStatusUpdate') ? data['lastStatusUpdate'] : null;

                              String statusText = isSafe ? "Safe" : "In Danger";
                              Color statusColor = isSafe ? Colors.green : Colors.red;
                              IconData statusIcon = isSafe ? Icons.check_circle : Icons.warning;

                              // How long ago was their status updated
                              String lastSeen = "";
                              if (lastUpdate != null) {
                                final diff = DateTime.now().difference(lastUpdate.toDate());
                                if (diff.inMinutes < 1) {
                                  lastSeen = "Just now";
                                } else if (diff.inMinutes < 60) {
                                  lastSeen = "${diff.inMinutes}m ago";
                                } else if (diff.inHours < 24) {
                                  lastSeen = "${diff.inHours}h ago";
                                } else {
                                  lastSeen = "${diff.inDays}d ago";
                                }
                              }

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: statusColor.withOpacity(0.2),
                                  child: Icon(
                                    Icons.person,
                                    color: statusColor,
                                  ),
                                ),
                                title: Text(
                                  data['username'] ?? 'Unknown',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  lastSeen.isNotEmpty
                                      ? "$statusText • Updated $lastSeen"
                                      : statusText,
                                ),
                                trailing: Icon(
                                  statusIcon,
                                  color: statusColor,
                                  size: 28,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
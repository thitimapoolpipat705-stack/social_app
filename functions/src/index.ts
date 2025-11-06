// Support both CommonJS and ESM-shaped exports for firebase-functions
const _functionsImport = require('firebase-functions');
const functions = (_functionsImport && _functionsImport.default) ? _functionsImport.default : _functionsImport;
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

// ---------- Helper ----------
// ฟังก์ชันเพิ่มหรือลดจำนวนในฟิลด์ของเอกสารใน `users`
async function incUser(uid, field, by) {
  const ref = db.collection('users').doc(uid);
  await ref.set(
    { [field]: admin.firestore.FieldValue.increment(by) },
    { merge: true }
  );
}

// ฟังก์ชันเพิ่ม Notification ให้ผู้ใช้
async function addNotification(targetUid, payload) {
  const ref = db
    .collection('users')
    .doc(targetUid)
    .collection('notifications')
    .doc();
  await ref.set({
    ...payload,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ---------- FOLLOW COUNT ----------
// เมื่อมีคนติดตาม (เพิ่มจำนวน followers)
exports.onFollowerAdded = functions.firestore
  .document('users/{uid}/followers/{followerUid}')
  .onCreate(async (snap, ctx) => {
    const { uid, followerUid } = ctx.params;
    await incUser(uid, 'followersCount', 1);

    const userSnap = await db.collection('users').doc(followerUid).get();
    const followerName = userSnap.data()?.displayName || 'Someone';
    await addNotification(uid, {
      type: 'follow',
      fromUid: followerUid,
      fromName: followerName,
      title: 'started following you',
      body: '',
    });
  });

exports.onFollowerRemoved = functions.firestore
  .document('users/{uid}/followers/{followerUid}')
  .onDelete(async (snap, ctx) => {
    const { uid } = ctx.params;
    await incUser(uid, 'followersCount', -1);
  });

// เมื่อมีการติดตามคนอื่น (เพิ่มจำนวน following)
exports.onFollowingAdded = functions.firestore
  .document('users/{uid}/following/{targetUid}')
  .onCreate(async (snap, ctx) => {
    const { uid } = ctx.params;
    await incUser(uid, 'followingCount', 1);
  });

exports.onFollowingRemoved = functions.firestore
  .document('users/{uid}/following/{targetUid}')
  .onDelete(async (snap, ctx) => {
    const { uid } = ctx.params;
    await incUser(uid, 'followingCount', -1);
  });

// ---------- FOLLOW REQUEST ----------
// การอนุมัติคำขอติดตาม
exports.approveFollowRequest = functions.https.onCall(async (data, context) => {
  if (!context.auth)
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required');

  const ownerUid = context.auth.uid;
  const followerUid = data?.followerUid;
  if (!followerUid)
    throw new functions.https.HttpsError('invalid-argument', 'followerUid required');

  const reqRef = db
    .collection('users')
    .doc(ownerUid)
    .collection('followRequests')
    .doc(followerUid);
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists || reqSnap.data().status !== 'pending') {
    throw new functions.https.HttpsError('failed-precondition', 'No pending request');
  }

  const batch = db.batch();
  batch.delete(reqRef);
  batch.set(
    db.collection('users').doc(ownerUid).collection('followers').doc(followerUid),
    { createdAt: admin.firestore.FieldValue.serverTimestamp() }
  );
  batch.set(
    db.collection('users').doc(followerUid).collection('following').doc(ownerUid),
    { createdAt: admin.firestore.FieldValue.serverTimestamp() }
  );
  await batch.commit();
  return { ok: true };
});

  exports.reportPost = functions.https.onCall(async (data, context) => {
  const { postId, reason, detail } = data;

  const reportRef = db.collection('postReports').doc();
  await reportRef.set({
    postId,
    reason,
    detail,
    reportedBy: context.auth.uid,
    status: 'open', // หรือ 'pending', 'resolved'
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});
  
  // ฟังก์ชันค้นหาผู้ใช้งานจากการแท็กในคอมเมนต์
function _extractMentions(text) {
  const re = /@([a-zA-Z0-9_]+)/g;  // Regular expression สำหรับค้นหา @username
  let mentions = [];
  let match;
  while ((match = re.exec(text)) !== null) {
    mentions.push(match[1]);  // เก็บชื่อผู้ใช้ที่ถูกแท็กใน array
  }
  return mentions;
}

// ฟังก์ชันการสร้างคอมเมนต์ในโพสต์
exports.onCommentCreated = functions.firestore
  .document('posts/{postId}/comments/{commentId}')
  .onCreate(async (snap, ctx) => {
    const { postId } = ctx.params;
    const commentData = snap.data();
    const text = commentData.text || '';

    // ดึงรายชื่อผู้ใช้ที่ถูกแท็กจากข้อความ
    const mentions = _extractMentions(text);
    
    for (const username of mentions) {
      // ค้นหาผู้ใช้จากชื่อที่ถูกแท็ก
      const userRef = await db.collection('users').where('username', '==', username).get();
      
      if (!userRef.empty) {
        const targetUid = userRef.docs[0].id;  // รับ UID ของผู้ใช้ที่ถูกแท็ก
        // ส่งการแจ้งเตือนไปยังผู้ใช้ที่ถูกแท็ก
        await addNotification(targetUid, {
          type: 'mention',
          fromUid: commentData.authorId,
          fromName: commentData.authorName,
          postId,
          title: `You were mentioned in a comment`,
          body: text,
        });
      }
    }
  });





// ---------- LIKE / COMMENT NOTIFICATION ----------
// เมื่อมีคนไลค์โพสต์
exports.onPostLiked = functions.firestore
  .document('posts/{postId}/reactions/{uid}')
  .onCreate(async (snap, ctx) => {
    const { postId, uid } = ctx.params;
    const postSnap = await db.collection('posts').doc(postId).get();
    if (!postSnap.exists) return;

    const postData = postSnap.data();
    const postOwner = postData.authorId;
    if (postOwner === uid) return; // ไม่ต้องแจ้งเตือนตัวเอง

    const userSnap = await db.collection('users').doc(uid).get();
    const likerName = userSnap.data()?.displayName || 'Someone';
    const thumbUrl = Array.isArray(postData.media)
      ? postData.media[0]?.url || ''
      : postData.media || '';

    await addNotification(postOwner, {
      type: 'like',
      fromUid: uid,
      fromName: likerName,
      postId,
      postThumbUrl: thumbUrl,
      title: 'liked your post',
      body: '',
    });
  });

// เมื่อมีคนคอมเมนต์โพสต์
exports.onPostCommented = functions.firestore
  .document('posts/{postId}/comments/{commentId}')
  .onCreate(async (snap, ctx) => {
    const { postId } = ctx.params;
    const commentData = snap.data();
    const fromUid = commentData.authorId;
    const text = commentData.text || '';

    const postSnap = await db.collection('posts').doc(postId).get();
    if (!postSnap.exists) return;

    const postData = postSnap.data();
    const postOwner = postData.authorId;
    if (postOwner === fromUid) return; // ไม่แจ้งเตือนเจ้าของเอง

    const userSnap = await db.collection('users').doc(fromUid).get();
    const fromName = userSnap.data()?.displayName || 'Someone';
    const thumbUrl = Array.isArray(postData.media)
      ? postData.media[0]?.url || ''
      : postData.media || '';

    await addNotification(postOwner, {
      type: 'comment',
      fromUid,
      fromName,
      postId,
      postThumbUrl: thumbUrl,
      title: 'commented on your post',
      body: text.substring(0, 60),
    });
  });

// ---------- เพิ่มฟังก์ชันการเพิ่มจำนวนโพสต์ใน `users` ----------
exports.onPostCreated = functions.firestore
  .document('posts/{postId}')
  .onCreate(async (snap, ctx) => {
    const authorId = snap.data().authorId;  // ดึง authorId ของโพสต์
    await incUser(authorId, 'postsCount', 1);  // อัปเดตจำนวนโพสต์
  });

// ---------- CHAT MESSAGE -> FCM & Notification ----------
// Triggered when a new message is created under conversations/{cid}/messages/{mid}
exports.onChatMessageCreated = functions.firestore
  .document('conversations/{cid}/messages/{mid}')
  .onCreate(async (snap, ctx) => {
    const { cid, mid } = ctx.params;
    const msg = snap.data() || {};
    const senderId = msg.senderId;
    const text = (msg.text || '').toString();
    const media = Array.isArray(msg.media) ? msg.media : [];

    // Determine a brief body for the notification
  const body = (text.length === 0) ? (media.length > 0 ? '[Media]' : '') : (text.length > 120 ? text.substring(0, 120) + '...' : text);

    // Load conversation to find recipients
    const convRef = db.collection('conversations').doc(cid);
    const convSnap = await convRef.get();
    if (!convSnap.exists) return;
    const conv = convSnap.data() || {};
    const members = Array.isArray(conv.members) ? conv.members : [];

    // Get sender name
    let senderName = 'Someone';
    try {
      const s = await db.collection('users').doc(senderId).get();
      const sd = s.data() || {};
      senderName = sd.displayName || sd.name || senderName;
    } catch (e) {
      // ignore
    }

    // For every member except sender, send FCM and create in-app notification
    for (const targetUid of members) {
      if (!targetUid || targetUid === senderId) continue;

      // 1) Create notification document (for in-app UI)
      await addNotification(targetUid, {
        type: 'chat',
        fromUid: senderId,
        fromName: senderName,
        title: senderName,
        body: body,
        extra: { chatId: cid, messageId: mid },
      });

      // 2) Send FCM to tokens saved on user doc
      try {
        const userSnap = await db.collection('users').doc(targetUid).get();
        const udata = userSnap.data() || {};
        const tokens = Array.isArray(udata.fcmTokens) ? udata.fcmTokens.filter(Boolean) : [];
        if (tokens.length === 0) continue;

        const payload = {
          notification: {
            title: senderName,
            body: body || '[New message]',
          },
          data: {
            type: 'chat',
            chatId: cid,
            messageId: mid,
            senderId: senderId,
            senderName: senderName,
            preview: body,
          },
        };

        // sendMulticast supports up to 500 tokens
        const res = await admin.messaging().sendMulticast({
          tokens: tokens,
          notification: payload.notification,
          data: payload.data,
        });

        // Optionally clean up invalid tokens
        if (res.failureCount > 0) {
          const toRemove: string[] = [];
          res.responses.forEach((r, i) => {
            if (!r.success) {
              const err = r.error;
              // common errors: 'messaging/registration-token-not-registered'
              if (err && err.code && (err.code === 'messaging/registration-token-not-registered' || err.code === 'messaging/invalid-registration-token')) {
                toRemove.push(tokens[i]);
              }
            }
          });
          if (toRemove.length > 0) {
            await db.collection('users').doc(targetUid).update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...toRemove) });
          }
        }
      } catch (e) {
        console.warn('Failed to send FCM for chat message', e);
      }
    }
  });

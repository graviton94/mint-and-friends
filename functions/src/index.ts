/**
 * 민트앤프렌즈 Cloud Functions (Blaze 요금제 필요)
 *
 * - kakaoLogin   : 앱이 보낸 카카오 액세스 토큰을 카카오 서버에서 검증하고 Firebase 커스텀 토큰을 발급한다.
 *                  uid = "kakao:<카카오 회원번호>"
 * - deleteAccount: 로그인한 사용자의 게임 데이터(users/{uid})와 Firebase 계정을 삭제한다.
 *                  (Google Play 정책: 앱 안에서 계정 삭제 제공 필수)
 *
 * 배포: firebase deploy --only functions
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";

initializeApp();
setGlobalOptions({ region: "asia-northeast3", maxInstances: 10 });

interface KakaoMe {
  id: number;
  kakao_account?: {
    profile?: { nickname?: string; profile_image_url?: string };
    email?: string;
    is_email_verified?: boolean;
  };
}

export const kakaoLogin = onCall<{ accessToken?: string }>(async (req) => {
  const accessToken = req.data?.accessToken;
  if (!accessToken || typeof accessToken !== "string") {
    throw new HttpsError("invalid-argument", "accessToken is required");
  }

  // 1) 토큰 검증 + 회원 정보 (카카오 REST API)
  const res = await fetch("https://kapi.kakao.com/v2/user/me", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    throw new HttpsError("unauthenticated", `kakao token rejected (${res.status})`);
  }
  const me = (await res.json()) as KakaoMe;
  if (!me.id) throw new HttpsError("unauthenticated", "kakao user id missing");

  const uid = `kakao:${me.id}`;
  const auth = getAuth();

  // 2) Firebase 사용자 생성/갱신 (표시 이름만 저장, 이메일은 동의한 경우에만)
  const profile = {
    displayName: me.kakao_account?.profile?.nickname,
    photoURL: me.kakao_account?.profile?.profile_image_url,
  };
  try {
    await auth.updateUser(uid, profile);
  } catch (e: unknown) {
    if ((e as { code?: string }).code === "auth/user-not-found") {
      await auth.createUser({ uid, ...profile });
    } else {
      throw e;
    }
  }

  // 3) 커스텀 토큰 발급
  const token = await auth.createCustomToken(uid, { provider: "kakao" });
  return { token };
});

export const deleteAccount = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "login required");
  await getFirestore().collection("users").doc(uid).delete();
  await getAuth().deleteUser(uid);
  return { ok: true };
});

# 릴리스 빌드 코드 축소(R8) 규칙.

# WorkManager(광고·Play 서비스가 앱 시작 때 초기화)는 Room 이 만든 WorkDatabase_Impl 을
# 이름으로 찾아 기본 생성자로 만든다. R8 이 이것을 지우면 앱이 실행 직후 꺼진다
# ("Failed to create an instance of androidx.work.impl.WorkDatabase").
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.** extends androidx.room.RoomDatabase { *; }
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-keep class * extends androidx.work.InputMerger { <init>(); }

# 카카오 SDK(Gson 으로 응답 모델을 읽음)
-keep class com.kakao.sdk.**.model.** { *; }
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod

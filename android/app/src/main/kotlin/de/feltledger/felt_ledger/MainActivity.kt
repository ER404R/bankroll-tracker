package de.feltledger.felt_ledger

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricPrompt
import android.os.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
 private var notificationResult: MethodChannel.Result? = null
 override fun configureFlutterEngine(engine: FlutterEngine) {
  super.configureFlutterEngine(engine)
  MethodChannel(engine.dartExecutor.binaryMessenger,"feltledger/device").setMethodCallHandler { call,result ->
   when(call.method) {
    "appInfo" -> {val info=packageManager.getPackageInfo(packageName,0);result.success(mapOf("version" to info.versionName,"installedAt" to info.firstInstallTime))}
    "authenticate" -> {
     if(Build.VERSION.SDK_INT < 30) {result.error("unsupported","Geräteschutz benötigt Android 11 oder neuer.",null)}
     else {
      val keyguard=getSystemService(KeyguardManager::class.java)
      if(!keyguard.isDeviceSecure) {result.error("not_enrolled","Bitte zuerst Android-Gerätesperre oder Biometrie einrichten.",null)}
      else {
       val prompt=BiometricPrompt.Builder(this).setTitle("Bankroll Tracker entsperren").setSubtitle("Deine lokalen Bankroll-Daten schützen").setAllowedAuthenticators(android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG or android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL).build()
       prompt.authenticate(CancellationSignal(),mainExecutor,object:BiometricPrompt.AuthenticationCallback(){
        override fun onAuthenticationSucceeded(r:BiometricPrompt.AuthenticationResult){result.success(true)}
        override fun onAuthenticationError(code:Int,message:CharSequence){result.success(false)}
       })
      }
     }
    }
    "notifications" -> {
     if(Build.VERSION.SDK_INT>=33&&checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED){notificationResult=result;requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),701)}else result.success(true)
    }
    "reminder" -> {
     val at=call.argument<Number>("at")!!.toLong()
     val intent=PendingIntent.getBroadcast(this,1,Intent(this,BreakReminder::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
     getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,intent)
     result.success(null)
    }
    "cancelReminder" -> {val intent=PendingIntent.getBroadcast(this,1,Intent(this,BreakReminder::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE);getSystemService(AlarmManager::class.java).cancel(intent);result.success(null)}
    else -> result.notImplemented()
   }
  }
 }
 override fun onRequestPermissionsResult(code:Int,permissions:Array<out String>,grants:IntArray){super.onRequestPermissionsResult(code,permissions,grants);if(code==701){notificationResult?.success(grants.isNotEmpty()&&grants[0]==PackageManager.PERMISSION_GRANTED);notificationResult=null}}
}
class BreakReminder: BroadcastReceiver(){
 override fun onReceive(context:Context,intent:Intent){
  val manager=context.getSystemService(NotificationManager::class.java)
  manager.createNotificationChannel(NotificationChannel("breaks","Pausenerinnerungen",NotificationManager.IMPORTANCE_DEFAULT))
  val launch=PendingIntent.getActivity(context,1,Intent(context,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE)
  val n=Notification.Builder(context,"breaks").setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle("Deine Pause endet bald").setContentText("Noch ungefähr zwei Minuten bis zum geplanten Pausenende.").setContentIntent(launch).setAutoCancel(true).build()
  if(Build.VERSION.SDK_INT<33||context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED)manager.notify(1,n)
 }
}

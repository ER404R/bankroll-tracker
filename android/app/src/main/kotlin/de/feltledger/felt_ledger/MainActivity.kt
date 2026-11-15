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
 private var documentResult: MethodChannel.Result? = null
 private var documentBytes: ByteArray? = null
 private var notificationResult: MethodChannel.Result? = null
 override fun configureFlutterEngine(engine: FlutterEngine) {
  super.configureFlutterEngine(engine)
  MethodChannel(engine.dartExecutor.binaryMessenger,"feltledger/device").setMethodCallHandler { call,result ->
   when(call.method) {
    "pickImportFile", "saveDocument" -> {
     if(documentResult != null) { result.error("busy", "Dateiauswahl läuft bereits", null) }
     else {
      val saving = call.method == "saveDocument"
      documentResult = result
      documentBytes = if(saving) call.argument<ByteArray>("bytes") else null
      val intent = Intent(if(saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
       addCategory(Intent.CATEGORY_OPENABLE)
       type = if(saving) "application/json" else "*/*"
       putExtra(Intent.EXTRA_LOCAL_ONLY, true)
       if(saving) putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "bankroll-import.json")
      }
      try { startActivityForResult(intent, if(saving) 703 else 702) }
      catch(e: Exception) { documentResult=null;documentBytes=null;result.error("document", "Dateiauswahl nicht verfügbar", null) }
     }
    }
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
 @Deprecated("Activity result bridge for Flutter method channel")
 override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
  super.onActivityResult(requestCode, resultCode, data)
  if(requestCode != 702 && requestCode != 703) return
  val result = documentResult ?: return
  val bytes = documentBytes
  documentResult = null
  documentBytes = null
  val uri = data?.data
  if(resultCode != RESULT_OK || uri == null) { result.success(if(requestCode==703) false else null); return }
  // Provider IO runs off the main thread; source is copied immediately, no broad permission.
  Thread {
   try {
    if(requestCode == 702) {
     val input = contentResolver.openInputStream(uri) ?: error("Datei nicht lesbar")
     val output = java.io.ByteArrayOutputStream()
     input.use { stream ->
      val buffer = ByteArray(8192)
      while(true) {
       val n = stream.read(buffer)
       if(n < 0) break
       if(output.size() + n > 16*1024*1024) error("Datei größer als 16 MiB")
       output.write(buffer,0,n)
      }
     }
     val content = output.toByteArray()
     runOnUiThread { result.success(content) }
    } else {
     val output = contentResolver.openOutputStream(uri, "wt") ?: error("Datei nicht schreibbar")
     output.use { it.write(bytes ?: error("Keine Daten")) }
     runOnUiThread { result.success(true) }
    }
   } catch(e: Exception) { runOnUiThread { result.error("document", e.message ?: "Dateifehler", null) } }
  }.start()
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

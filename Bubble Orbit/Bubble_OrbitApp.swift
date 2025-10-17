import SwiftUI
import Firebase
import AppsFlyerLib
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications

@main
struct Bubble_OrbitApp: App {
    
    @UIApplicationDelegateAdaptor(ApplicationDelegate.self) var applicationDelegate
    
    var body: some Scene {
        WindowGroup {
            LaunchView()
        }
    }
}

class ApplicationDelegate: UIResponder, UIApplicationDelegate, AppsFlyerLibDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    
    private var attribData: [AnyHashable: Any] = [:]
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        
        AppsFlyerLib.shared().appsFlyerDevKey = "t7wmt7Ap8ZPiRfgTXoMo67"
        AppsFlyerLib.shared().appleAppID = "6753303972"
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().start()
        
        // Messaging setup
        Messaging.messaging().delegate = self
        
        UNUserNotificationCenter.current().delegate = self
        
        application.registerForRemoteNotifications()
        
        if let notifPayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            processNotifPayload(notifPayload)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activateTracking),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        return true
    }
    
    
    @objc private func activateTracking() {
        AppsFlyerLib.shared().start()
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { _ in
            }
        }
    }
    
    // AppsFlyer callbacks
    func onConversionDataSuccess(_ data: [AnyHashable: Any]) {
        attribData = data
        NotificationCenter.default.post(name: Notification.Name("ConversionDataReceived"), object: nil, userInfo: ["conversionData": attribData])
    }
    
    func onConversionDataFail(_ error: Error) {
        NotificationCenter.default.post(name: Notification.Name("ConversionDataReceived"), object: nil, userInfo: ["conversionData": [:]])
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, err in
            if let _ = err {
            }
            UserDefaults.standard.set(token, forKey: "fcm_token")
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }
    
    // Notification handling
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let payload = notification.request.content.userInfo
        processNotifPayload(payload)
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let payload = response.notification.request.content.userInfo
        processNotifPayload(payload)
        completionHandler()
    }
    
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        processNotifPayload(userInfo)
        completionHandler(.newData)
    }
    
}

extension ApplicationDelegate {
    
    
    private func processNotifPayload(_ payload: [AnyHashable: Any]) {
        var linkStr: String?
        if let link = payload["url"] as? String {
            linkStr = link
        } else if let info = payload["data"] as? [String: Any], let link = info["url"] as? String {
            linkStr = link
        }
        
        if let linkStr = linkStr {
            UserDefaults.standard.set(linkStr, forKey: "temp_url")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NotificationCenter.default.post(name: NSNotification.Name("LoadTempURL"), object: nil, userInfo: ["tempUrl": linkStr])
            }
        }
    }
    
}

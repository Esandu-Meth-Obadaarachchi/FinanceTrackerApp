// ⚠️ PLACEHOLDER — replaced automatically by `flutterfire configure`.
//
// This file is regenerated with your real Firebase project keys when you run:
//   flutterfire configure
// Until then the app will not connect to Firebase. The placeholder only
// exists so the project compiles.
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAxLmoHppGJw_5qow71j55EQyFELepo0N8',
    appId: '1:984237745523:web:28156c4a0589270a355106',
    messagingSenderId: '984237745523',
    projectId: 'fintrack-05220041',
    authDomain: 'fintrack-05220041.firebaseapp.com',
    storageBucket: 'fintrack-05220041.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAyWPNOkIixiV2-xoz3BJVp5V0PhIuyUv8',
    appId: '1:984237745523:android:26ddcda375f007aa355106',
    messagingSenderId: '984237745523',
    projectId: 'fintrack-05220041',
    storageBucket: 'fintrack-05220041.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: 'PLACEHOLDER',
    messagingSenderId: 'PLACEHOLDER',
    projectId: 'placeholder',
    iosBundleId: 'com.example.financialtracker',
  );
}
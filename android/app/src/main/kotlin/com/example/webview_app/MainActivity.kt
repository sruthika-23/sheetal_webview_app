package com.example.webview_app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            startLockTask()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
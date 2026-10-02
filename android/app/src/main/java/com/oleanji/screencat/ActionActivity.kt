package com.oleanji.screencat

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle

/**
 * A see-through activity that only passes a routine on to the service and
 * closes. Notification buttons go through it because starting an activity
 * closes the notification shade, so you do not have to swipe it shut.
 */
class ActionActivity : Activity() {
    companion object {
        fun intent(context: Context, routine: Routine): Intent =
            Intent(context, ActionActivity::class.java)
                .putExtra(CatService.EXTRA_ROUTINE, routine.key)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val routine = Routine.from(intent.getStringExtra(CatService.EXTRA_ROUTINE))
        if (routine != null) CatService.start(this, CatService.ACTION_RUN, routine)
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}

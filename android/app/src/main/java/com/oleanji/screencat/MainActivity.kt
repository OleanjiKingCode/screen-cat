package com.oleanji.screencat

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

/**
 * The settings screen: start and stop, run a routine now, Mr. Robot, the mode,
 * and the settings that matter most. Everything is saved to screencat.json
 * with the same keys as the Mac's ~/.screencat.json; the raw file is editable
 * at the bottom for the rest.
 */
class MainActivity : Activity() {
    private val bg = rgb(0x14161F)
    private val card = rgb(0x1E2130)
    private val textColour = gray(0.92f)
    private val dim = gray(0.6f)
    private val accent = rgb(0xA87BE0)

    private lateinit var status: TextView
    private lateinit var permissionButton: Button
    private val numberFields = LinkedHashMap<String, EditText>()
    private val colourFields = LinkedHashMap<String, EditText>()
    private lateinit var idleCrawlBox: CheckBox
    private lateinit var shadowBox: CheckBox
    private lateinit var modeGroup: RadioGroup
    private lateinit var rawJson: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Config.writeDefaultFileIfMissing(this)
        window.statusBarColor = bg
        window.navigationBarColor = bg
        setContentView(build())
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun build(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(24), dp(16), dp(32))
        }
        val scroll = ScrollView(this).apply {
            setBackgroundColor(bg)
            fitsSystemWindows = true
            addView(root)
        }

        root.addView(label("Screen Cat", 26f, textColour, bold = true))
        status = label("", 14f, dim)
        root.addView(status)
        permissionButton = button("Allow display over other apps") {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        }
        root.addView(permissionButton)

        root.addView(section("Cat"))
        root.addView(row(
            button("Start") { startCat(null) },
            button("Stop") {
                if (CatService.running) startService(CatService.intent(this, CatService.ACTION_STOP))
                status.postDelayed({ refresh() }, 300)
            },
            button("Pause") { if (CatService.running) startService(CatService.intent(this, CatService.ACTION_PAUSE)) },
        ))

        root.addView(section("Play a routine now"))
        root.addView(row(
            button("Walk") { startCat(Routine.STROLL) },
            button("Nap") { startCat(Routine.NAP) },
            button("Ball") { startCat(Routine.BALL) },
        ))
        root.addView(row(
            button("Feed") { startCat(Routine.HUNGRY) },
            button("Break stuff") { startCat(Routine.CRAWL) },
        ))
        root.addView(button("Crawl until I touch something") { startCat(Routine.IDLE_CRAWL) })
        root.addView(button("Mr. Robot (3 min hack, starts now)") { startCat(Routine.MR_ROBOT) }.apply {
            setTextColor(rgb(0x39FF7A))
        })

        val c = Config.load(this)

        root.addView(section("Mode"))
        modeGroup = RadioGroup(this).apply { orientation = RadioGroup.HORIZONTAL }
        val normal = radio("Normal", 101)
        val crawler = radio("Crawler", 102)
        modeGroup.addView(normal)
        modeGroup.addView(crawler)
        modeGroup.check(if (c.mode == "crawler") 102 else 101)
        root.addView(modeGroup)

        root.addView(section("Idle crawl"))
        idleCrawlBox = check("Start the glitch takeover when the phone is left alone", c.idleCrawl)
        root.addView(idleCrawlBox)
        numberFields["idleCrawlSeconds"] = numberField(root, "idleCrawlSeconds (no touch for this long, at least 15)", c.idleCrawlSeconds.toDouble())
        numberFields["glitchStyleSeconds"] = numberField(root, "glitchStyleSeconds (each style plays this long)", c.glitchStyleSeconds.toDouble())
        numberFields["growScale"] = numberField(root, "growScale (1 to 4)", c.growScale.toDouble())

        root.addView(section("Outfit"))
        numberFields["chainChance"] = numberField(root, "chainChance (0 to 1)", c.chainChance)
        numberFields["glassesChance"] = numberField(root, "glassesChance (0 to 1)", c.glassesChance)

        root.addView(section("Colours"))
        colourFields["furColor"] = colourField(root, "furColor", c.furColor)
        colourFields["furShadeColor"] = colourField(root, "furShadeColor", c.furShadeColor)
        colourFields["outlineColor"] = colourField(root, "outlineColor", c.outlineColor)
        colourFields["innerColor"] = colourField(root, "innerColor", c.innerColor)
        colourFields["eyeColor"] = colourField(root, "eyeColor", c.eyeColor)
        colourFields["ballColor"] = colourField(root, "ballColor", c.ballColor)
        shadowBox = check("Shadow under the cat", c.shadow)
        root.addView(shadowBox)

        root.addView(button("Save settings") { saveFields() })

        root.addView(section("All settings (screencat.json)"))
        root.addView(label("Same keys as the Mac's ~/.screencat.json. Keys that mean nothing on Android are kept but ignored.", 12f, dim))
        rawJson = EditText(this).apply {
            setTextColor(textColour)
            textSize = 12f
            typeface = Typeface.MONOSPACE
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            isSingleLine = false
            gravity = Gravity.TOP
            background = rounded(card)
            setPadding(dp(10), dp(10), dp(10), dp(10))
        }
        root.addView(rawJson, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(8)
        })
        root.addView(button("Save JSON") { saveJson() })
        root.addView(label("Sprites: \"Cat Pack\" by Glem / octopusINKUS. See CREDIT.txt.", 12f, dim))
        return scroll
    }

    private fun refresh() {
        val allowed = Settings.canDrawOverlays(this)
        permissionButton.visibility = if (allowed) View.GONE else View.VISIBLE
        status.text = when {
            !allowed -> "Needs \"Display over other apps\" before the cat can come out."
            CatService.running -> "Running. Pause, stop and Mr. Robot are also on the notification."
            else -> "Stopped."
        }
        rawJson.setText(Config.readRaw(this)?.toString(2) ?: Config().toJson().toString(2))
    }

    private fun startCat(routine: Routine?) {
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "Allow \"Display over other apps\" first", Toast.LENGTH_SHORT).show()
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            return
        }
        if (routine == null) CatService.start(this) else CatService.start(this, CatService.ACTION_RUN, routine)
        status.postDelayed({ refresh() }, 300)
    }

    private fun saveFields() {
        val values = HashMap<String, Any>()
        for ((key, field) in numberFields) {
            val v = field.text.toString().trim().toDoubleOrNull()
            if (v == null) {
                Toast.makeText(this, "$key is not a number", Toast.LENGTH_SHORT).show()
                return
            }
            values[key] = v
        }
        for ((key, field) in colourFields) {
            val text = field.text.toString().trim()
            if (parseHex(text) == null) {
                Toast.makeText(this, "$key should look like #A87BE0", Toast.LENGTH_SHORT).show()
                return
            }
            values[key] = text
        }
        values["mode"] = if (modeGroup.checkedRadioButtonId == 102) "crawler" else "normal"
        values["idleCrawl"] = idleCrawlBox.isChecked
        values["shadow"] = shadowBox.isChecked
        Config.update(this, values)
        afterSave()
    }

    private fun saveJson() {
        val parsed = try {
            JSONObject(rawJson.text.toString())
        } catch (e: Exception) {
            Toast.makeText(this, "Not valid JSON: ${e.message}", Toast.LENGTH_LONG).show()
            return
        }
        Config.file(this).writeText(parsed.toString(2))
        afterSave()
        // Rebuild so the fields above show the new values.
        setContentView(build())
        refresh()
    }

    private fun afterSave() {
        if (CatService.running) startService(CatService.intent(this, CatService.ACTION_RELOAD))
        Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show()
        refresh()
    }

    // Small view helpers ------------------------------------------------------

    private fun rounded(colour: Int) = GradientDrawable().apply {
        setColor(colour)
        cornerRadius = dp(10).toFloat()
    }

    private fun label(text: String, size: Float, colour: Int, bold: Boolean = false) = TextView(this).apply {
        this.text = text
        textSize = size
        setTextColor(colour)
        if (bold) typeface = Typeface.DEFAULT_BOLD
        setPadding(0, dp(4), 0, dp(4))
    }

    private fun section(text: String) = label(text.uppercase(), 13f, accent, bold = true).apply {
        setPadding(0, dp(20), 0, dp(6))
    }

    private fun button(text: String, onClick: () -> Unit) = Button(this).apply {
        this.text = text
        isAllCaps = false
        setTextColor(textColour)
        background = rounded(card)
        setOnClickListener { onClick() }
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)).apply {
            topMargin = dp(6)
        }
    }

    private fun row(vararg views: View) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        for ((i, v) in views.withIndex()) {
            addView(v, LinearLayout.LayoutParams(0, dp(48), 1f).apply {
                topMargin = dp(6)
                if (i > 0) marginStart = dp(6)
            })
        }
    }

    private fun radio(text: String, id: Int) = RadioButton(this).apply {
        this.text = text
        this.id = id
        setTextColor(textColour)
        setPadding(dp(4), 0, dp(16), 0)
    }

    private fun check(text: String, on: Boolean) = CheckBox(this).apply {
        this.text = text
        isChecked = on
        setTextColor(textColour)
    }

    private fun numberField(root: LinearLayout, title: String, value: Double): EditText {
        root.addView(label(title, 13f, dim))
        val field = EditText(this).apply {
            setText(if (value % 1.0 == 0.0) value.toLong().toString() else value.toString())
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            setTextColor(textColour)
            background = rounded(card)
            setPadding(dp(10), dp(8), dp(10), dp(8))
        }
        root.addView(field)
        return field
    }

    private fun colourField(root: LinearLayout, key: String, value: String): EditText {
        val swatch = View(this).apply { background = rounded(parseHex(value) ?: BLACK) }
        val field = EditText(this).apply {
            setText(value)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            setTextColor(textColour)
            typeface = Typeface.MONOSPACE
            background = rounded(card)
            setPadding(dp(10), dp(8), dp(10), dp(8))
            setOnFocusChangeListener { _, _ ->
                parseHex(text.toString())?.let { swatch.background = rounded(it) }
            }
        }
        val line = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(TextView(this@MainActivity).apply {
                text = key
                textSize = 13f
                setTextColor(dim)
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(swatch, LinearLayout.LayoutParams(dp(28), dp(28)).apply { marginEnd = dp(8) })
            addView(field, LinearLayout.LayoutParams(dp(130), ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        root.addView(line, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(6)
        })
        return field
    }
}

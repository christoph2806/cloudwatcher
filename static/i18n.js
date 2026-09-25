var currentLanguage = "";
var I18N = {
  de: {
    "settings": "Einstellungen",
    "charts": "Diagramme",
    "language": "Sprache",
    "prev": "Vortag",
    "today": "Heute",
    "next": "Folgetag",
    "date": "Datum",
    "calendar": "Kalender",
    "noMessage": "keine Nachricht",
    "safeUnknown": "Safe —",
    "switchUnknown": "Switch —",
    "safeStateOn": "Safe",
    "safeStateOff": "Unsafe",
    "safeOn": "sicher",
    "safeOff": "unsicher",
    "switchOn": "an",
    "switchOff": "aus",
    "up": "Nach oben",
    "down": "Nach unten",
    "noFieldsSelected": "Keine Felder ausgewählt.",
    "noData": "Keine Daten für diesen Tag.",
    "noNumbers": "Nachrichten vorhanden, aber ohne numerische Felder.",
    "messages": "Nachrichten",
    "unreadable": "nicht lesbar",
    "loading": "Laden …",
    "queryFailed": "Abfrage fehlgeschlagen",
    "saveFailed": "Speichern fehlgeschlagen",
    "saving": "Speichern …",
    "saved": "Gespeichert.",
    "loadFailed": "Einstellungen konnten nicht geladen werden.",
    "noFields": "Keine Felder vorhanden.",
    "chartMin": "Diagramm-Minimum",
    "chartMax": "Diagramm-Maximum",
    "diagrams": "Diagramme",
    "limitIn": "innerhalb der Grenzwerte",
    "limitOut": "außerhalb der Grenzwerte",
    "limitUnknown": "kein Grenzwert",
    "limits": "Grenzwerte",
    "limitsHelp": "Voreinstellung aus der Solo. Leere Felder werden nicht gezeichnet. Eine Linie, die weit außerhalb der Werte des Tages liegt, entfällt, damit die Kurve lesbar bleibt.",
    "save": "Speichern",
    "pageCharts": "CloudWatcher",
    "pageSettings": "CloudWatcher Einstellungen",
    "field.clouds": "Himmelstemperatur (Bewölkung)",
    "field.wind": "Wind",
    "field.gust": "Böen",
    "field.rawir": "Roh-Infrarot",
    "field.rain": "Regen",
    "field.light": "Helligkeit",
    "field.abspress": "Absolutdruck",
    "field.relpress": "Relativdruck",
    "field.safe": "Safe",
    "field.switch": "Switch",
    "field.temp": "Temperatur",
    "limit.unsafe": "Schalter",
    "limit.calm": "Ruhig",
    "limit.windy": "Windig",
    "limit.wind.very": "Sehr windig",
    "limit.clouds.clear": "Klar",
    "limit.clouds.cloudy": "Bewölkt",
    "limit.clouds.overcast": "Bedeckt",
    "limit.rain.dry": "Trocken",
    "limit.rain.wet": "Feucht",
    "limit.rain.rain": "Regen",
    "limit.light.dark": "Dunkel",
    "limit.light.light": "Hell",
    "limit.light.very": "Sehr hell",
    "limit.low": "Niedrig",
    "limit.medium": "Mittel",
    "limit.high": "Hoch",
    "info": "Erklärung",
    "close": "Schließen",
    "info.unknown": "Für diesen Wert liegt keine Erklärung vor.",
    "info.clouds": "Infrarotmessung des Himmels in °C, korrigiert mit der Umgebungstemperatur. Ein klarer Himmel ist kälter. Wolken strahlen mehr Wärme nach unten ab, deshalb steigt der Wert. Die Grenzen hängen vom Standort ab und stehen unter Einstellungen.",
    "info.temp": "Umgebungstemperatur in °C. Sie wird benutzt, um die Himmelstemperatur zu korrigieren. Mit dem optionalen Feuchte- und Drucksensor ist sie genauer als das Thermometer im Infrarotsensor.",
    "info.rawir": "Unkorrigierte Infrarottemperatur des Himmels in °C, bevor Offset und Umgebungskorrektur abgezogen werden. Die Bewölkungskurve benutzt den korrigierten Wert.",
    "info.wind": "Windgeschwindigkeit und Böen in km/h vom Anemometer. Die Linie ist der Wind, die gelben Punkte sind die Böen. Ab der Grenze „Schalter“ gilt der Wind als unsicher.",
    "info.rain": "Regenmesser als Rohwert, kapazitiv oder optisch. Trocken liegt der Wert hoch, Regen drückt ihn nach unten. Die Achse ist deshalb umgekehrt. Die Grenzen Trocken, Feucht und Regen müssen zum eigenen Sensor passen.",
    "info.light": "Helligkeit des Himmels als Rohwert. Ein größerer Wert bedeutet einen dunkleren Himmel, deshalb ist die Achse umgekehrt. Die Grenzen Dunkel, Hell und Sehr hell stehen in den Einstellungen.",
    "info.safe": "Gesamtentscheidung der Solo. 1 heißt sicher: alle eingestellten Grenzen sind eingehalten. 0 heißt unsicher: mindestens eine Grenze ist verletzt, zum Beispiel Wolken, Regen oder Wind.",
    "info.switch": "Schaltausgang der Solo. 1 heißt an, 0 heißt aus. Damit kann ein Dach oder ein anderes Gerät geschaltet werden. Die Schwelle je Messwert steht in den Einstellungen.",
    "info.hum": "Relative Luftfeuchte in Prozent vom optionalen Sensor. −1 bedeutet, dass kein Sensor angeschlossen ist. Hohe Feuchte hebt auch die Infrarotmessung eines klaren Himmels an.",
    "info.dewp": "Taupunkt in °C, berechnet aus Temperatur und Luftfeuchte. Liegt er nahe an der Gerätetemperatur, droht Beschlag. Ohne Feuchtesensor ist der Wert nicht brauchbar.",
    "info.abspress": "Absoluter Luftdruck am Standort, vom optionalen Sensor. 0 bedeutet, dass kein Sensor angeschlossen ist.",
    "info.relpress": "Zum Vergleich umgerechneter Luftdruck vom optionalen Sensor. Die Solo bezieht dabei die gewählte Umgebungstemperatur ein. 0 bedeutet, dass kein Sensor angeschlossen ist."
  },
  en: {
    "settings": "Settings",
    "charts": "Charts",
    "language": "Language",
    "prev": "Previous day",
    "today": "Today",
    "next": "Next day",
    "date": "Date",
    "calendar": "Calendar",
    "noMessage": "no message",
    "safeUnknown": "Safe —",
    "switchUnknown": "Switch —",
    "safeStateOn": "Safe",
    "safeStateOff": "Unsafe",
    "safeOn": "clear",
    "safeOff": "unsafe",
    "switchOn": "on",
    "switchOff": "off",
    "up": "Move up",
    "down": "Move down",
    "noFieldsSelected": "No fields selected.",
    "noData": "No data for this day.",
    "noNumbers": "Messages arrived, but none of the fields are numeric.",
    "messages": "messages",
    "unreadable": "unreadable",
    "loading": "Loading …",
    "queryFailed": "Query failed",
    "saveFailed": "Save failed",
    "saving": "Saving …",
    "saved": "Saved.",
    "loadFailed": "Settings could not be loaded.",
    "noFields": "No fields available.",
    "chartMin": "Chart minimum",
    "chartMax": "Chart maximum",
    "diagrams": "Charts",
    "limitIn": "within limits",
    "limitOut": "out of limits",
    "limitUnknown": "no limit",
    "limits": "Limits",
    "limitsHelp": "Defaults from the Solo. Empty fields are not drawn. A line far outside that day's values is omitted so the curve stays readable.",
    "save": "Save",
    "pageCharts": "CloudWatcher",
    "pageSettings": "CloudWatcher settings",
    "field.clouds": "Sky temperature (cloud cover)",
    "field.wind": "Wind",
    "field.gust": "Gusts",
    "field.rawir": "Raw Infrared",
    "field.rain": "Rain",
    "field.light": "Brightness",
    "field.abspress": "Absolute pressure",
    "field.relpress": "Relative pressure",
    "field.safe": "Safe",
    "field.switch": "Switch",
    "field.temp": "Temperature",
    "limit.unsafe": "Switch",
    "limit.calm": "Calm",
    "limit.windy": "Windy",
    "limit.wind.very": "Very windy",
    "limit.clouds.clear": "Clear",
    "limit.clouds.cloudy": "Cloudy",
    "limit.clouds.overcast": "Overcast",
    "limit.rain.dry": "Dry",
    "limit.rain.wet": "Wet",
    "limit.rain.rain": "Rain",
    "limit.light.dark": "Dark",
    "limit.light.light": "Light",
    "limit.light.very": "Very bright",
    "limit.low": "Low",
    "limit.medium": "Medium",
    "limit.high": "High",
    "info": "Explanation",
    "close": "Close",
    "info.unknown": "No explanation is available for this value.",
    "info.clouds": "Infrared sky temperature in °C, corrected with the ambient temperature. A clear sky reads colder. Clouds radiate more heat downward, so the value rises. The limits depend on the site and are set in Settings.",
    "info.temp": "Ambient temperature in °C. It is used to correct the sky temperature. With the optional humidity and pressure sensor it is more accurate than the thermometer inside the infrared sensor.",
    "info.rawir": "Uncorrected infrared sky temperature in °C, before the offset and the ambient correction are applied. The cloud-cover chart uses the corrected value.",
    "info.wind": "Wind speed and gusts in km/h from the anemometer. The line is the wind and the yellow dots are the gusts. Above the switch limit the wind is treated as unsafe.",
    "info.rain": "Rain sensor raw value, capacitive or optical. A dry sensor reads high and rain pushes the value down, so the axis is inverted. The dry, wet, and rain limits have to match your sensor.",
    "info.light": "Sky brightness as a raw value. A larger number means a darker sky, so the axis is inverted. The dark, light, and very-bright limits are in Settings.",
    "info.safe": "The Solo's overall decision. 1 means safe: every configured limit is met. 0 means unsafe: at least one limit is exceeded, for example clouds, rain, or wind.",
    "info.switch": "The Solo's switch output. 1 means on and 0 means off. It can operate a roof or other equipment. The threshold for each reading is in Settings.",
    "info.hum": "Relative humidity in percent from the optional sensor. −1 means no sensor is connected. High humidity also raises the infrared reading of a clear sky.",
    "info.dewp": "Dew point in °C, from temperature and humidity. When it is close to the equipment temperature, dew is likely. Without a humidity sensor the value is not useful.",
    "info.abspress": "Absolute atmospheric pressure at the site, from the optional sensor. 0 means no sensor is connected.",
    "info.relpress": "Pressure adjusted for comparison, from the optional sensor. The Solo uses the selected ambient temperature in that calculation. 0 means no sensor is connected."
  }
};

function currentLang() {
  if (currentLanguage === "de" || currentLanguage === "en") return currentLanguage;
  var nav = (navigator.language || "").toLowerCase();
  return nav.indexOf("de") === 0 ? "de" : "en";
}

function setLanguage(lang) {
  currentLanguage = lang === "de" || lang === "en" ? lang : "";
}

function uiLocale() {
  return currentLang() === "de" ? "de-DE" : "en-GB";
}

function t(key) {
  var lang = I18N[currentLang()] || I18N.en;
  if (lang[key]) return lang[key];
  if (I18N.en[key]) return I18N.en[key];
  return key;
}

function fieldTitle(field, fallback) {
  var key = "field." + field;
  var lang = I18N[currentLang()] || I18N.en;
  return lang[key] || fallback || field;
}

function limitName(field, id, fallback) {
  var lang = I18N[currentLang()] || I18N.en;
  var keys = ["limit." + field + "." + id];
  if (field === "gust") keys.push("limit.wind." + id);
  if (field === "relpress") keys.push("limit.abspress." + id);
  keys.push("limit." + id);
  for (var i = 0; i < keys.length; i++) {
    if (lang[keys[i]]) return lang[keys[i]];
  }
  return fallback || id;
}

function applyI18n() {
  var lang = currentLang();
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-i18n]").forEach(function (el) {
    el.textContent = t(el.getAttribute("data-i18n"));
  });
  document.querySelectorAll("[data-i18n-aria]").forEach(function (el) {
    el.setAttribute("aria-label", t(el.getAttribute("data-i18n-aria")));
  });
}

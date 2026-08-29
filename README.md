# Weather ETL Pipeline — Week 7 Project

## 1. Project Overview
This project builds a simple **ETL (Extract, Transform, Load) pipeline** that pulls
real-time current weather data from the OpenWeather API for all **54 African
capital cities**, cleans the data with Pandas, stores it in both CSV and SQLite
formats, and performs a comparative analysis across the continent.

## 2. Data Source
- **API:** [OpenWeather Current Weather Data API](https://openweathermap.org/current)
  (free tier)
- **Endpoint used:** `https://api.openweathermap.org/data/2.5/weather`
- **Fields retrieved:** city name, country code, temperature, "feels like"
  temperature, humidity, weather condition/description, wind speed, and the
  UTC timestamp of the reading.
- **Coverage:** all 54 African Union member state capitals, e.g. Nairobi (KE),
  Abuja (NG), Kigali (RW), Cairo (EG), Pretoria (ZA), and so on — see the full
  list in `weather_etl.py` / the notebook.

### A note on "current" vs. "historical" data
OpenWeather's **free** plan only exposes **current weather** and a 5-day/3-hour
forecast — it cannot return data for a past date (not even yesterday). Getting
historical data (e.g. a specific date last month, or a 6-month range) requires
their **paid** History API / History Bulk product, which needs a billed
subscription. To keep this project strictly on OpenWeather's free tier, we
scaled the pipeline **out** (54 cities) instead of back in time. Every time
you run the pipeline, it captures a live snapshot of "right now" across the
whole continent — which is itself a useful, repeatable ETL run (you could
schedule it daily to build up your own historical archive over time).

## 3. Tools Used
| Tool | Purpose |
|---|---|
| Python | Core programming language |
| `requests` | Calling the OpenWeather API |
| `pandas` | Cleaning and structuring the data |
| `sqlite3` | Loading data into a lightweight database |
| `matplotlib` | Quick "hottest capitals" chart |
| Google Colab / VS Code | Development environment |

## 4. ETL Process

### Extract
`extract_weather_data()` loops through all 54 `City,CountryCode` pairs and
sends a GET request to the OpenWeather API for each one, using
`units=metric` so temperature comes back in Celsius and wind speed in m/s.
A short `time.sleep(0.2)` between calls keeps well within the free plan's
60-calls/minute limit. Cities that fail to resolve are logged and skipped
rather than crashing the whole run.

### Transform
`transform_weather_data()` converts the raw JSON list into a tidy Pandas
DataFrame:
- Selects only the relevant fields (city, country, temperature, humidity,
  condition, description, wind speed, timestamp).
- Renames raw API keys (like `main.temp`) into clear column names
  (`temperature_celsius`).
- Converts numeric fields with `pd.to_numeric()` and the Unix timestamp into
  a real UTC `datetime` with `datetime.fromtimestamp()`.
- Title-cases the weather condition/description text for readability.
- Drops any rows where extraction failed, and sorts alphabetically by city.

### Load
`load_data()` saves the cleaned DataFrame to:
- `data/weather_data.csv` — a plain CSV for quick viewing/sharing.
- `data/weather_data.db` — a SQLite database (table: `weather_data`) for
  querying with SQL later.

### Analyze
`analyze_data()` compares all 54 cities and prints:
- The hottest and coolest capital.
- The most humid and windiest capital.
- The average temperature and humidity across the whole continent.
- The most common weather conditions right now, and how many capitals share
  each one.

## 5. Steps Taken (chronological, for the demo video)
1. Created a free OpenWeather account and generated an API key (see section 6
   below for exact sub-steps to narrate).
2. Confirmed the free plan's limits: current weather + 5-day forecast only,
   no past dates.
3. Compiled the full list of 54 African capital cities with their ISO
   country codes.
4. Wrote `extract_weather_data()` and ran it, watching each city return
   `OK` or `FAILED`.
5. Inspected the raw JSON structure to identify the fields needed
   (`main.temp`, `main.humidity`, `weather[0].description`, `wind.speed`, `dt`).
6. Wrote `transform_weather_data()` to reshape the JSON into a clean
   DataFrame with correct column names and data types.
7. Wrote `load_data()` to persist the DataFrame as CSV and SQLite.
8. Wrote `analyze_data()` to summarize temperature, humidity, and conditions
   across all 54 capitals.
9. Ran the full pipeline end-to-end and reviewed the output files in `data/`.

## 6. How to Get an OpenWeather API Key (walk through this on camera)
1. Go to **https://openweathermap.org/api**.
2. Click **"Sign Up"** (top right) and create a free account with your email.
3. Verify your email address via the confirmation link OpenWeather sends you.
4. Log in, then click your username (top right) → **"My API keys"**.
5. A **default key is generated automatically** when you sign up — copy it, or
   click **"Generate"** to create a new named key.
6. **Important:** a brand-new key can take up to ~10–60 minutes to activate.
   If you get a `401 Unauthorized` error right after creating it, wait a bit
   and try again.
7. Paste the key into the `API_KEY` variable in the notebook/script (or
   better, store it as an environment variable / Colab secret — see the
   Security Note below).

## 7. Key Findings
> Fill this in with your actual numbers after you run the pipeline —
> `analyze_data()` prints exactly this information for you.

- **Hottest capital:** _[city] at [X]°C_
- **Coolest capital:** _[city] at [X]°C_
- **Most humid capital:** _[city] at [X]% humidity_
- **Windiest capital:** _[city] at [X] m/s_
- **Continental average:** _[X]°C, [X]% humidity_
- **Most common conditions:** _[e.g. "Clear sky (18 cities), Scattered clouds
  (12 cities), ..."]_

## 8. Project Structure
```

```

## 9. How to Run
Google Colab (recommended for the demo video)**
1. Go to https://colab.research.google.com → File → Upload notebook →
   select `weather_etl_colab.ipynb`.
2. Run each cell top to bottom with Shift+Enter, narrating what each stage
   does as you go. The extract step takes ~15–20 seconds for all 54 cities.



## 10. Security Note
The API key in this repo's code is included directly so it's easy to explain
on camera. For a real production project (and before pushing to a **public**
GitHub repo), you should instead:
- Store the key in an environment variable (`OPENWEATHER_API_KEY`) and load it
  with `os.getenv("OPENWEATHER_API_KEY")` (already supported in
  `weather_etl.py`), **or**
- In Colab, use `Secrets` (key icon in the left sidebar) and
  `google.colab.userdata.get(...)`.

If you're worried this key has already been shared somewhere public, you can
regenerate a new one for free anytime from your OpenWeather account under
**"My API keys"**.

## 11. What I Learned About ETL Pipelines
> Use this section as talking points for your LinkedIn post — a few ideas to
> personalize:
- APIs return messy, deeply nested JSON — the "Transform" step is where most
  of the real work happens (flattening, renaming, fixing types).
- Free-tier APIs come with real constraints (here, no historical data) — part
  of being a good analyst is designing around those limits instead of
  fighting them, e.g. scaling city coverage instead of time coverage.
- Looping over many cities means you also need basic resilience (skip a
  failed city instead of crashing) — a small but important ETL habit.
- Storing data in more than one format (CSV *and* SQLite) makes it easier to
  reuse later — CSV for quick sharing, SQLite for querying with SQL.
- Small automation scripts like this are the foundation of larger, scheduled
  data pipelines (e.g. running this daily to build a historical weather
  archive over time).

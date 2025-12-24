# potapy
Uses Python to transform your CSV data from pota.app in to something a bit more graphical. Supports uploading activator logs as well as hunter logs.

### Installation

Requires Python to be installed.

Install required Python stuff:

```
pip install -r requirements.txt
```

Launch from command line:

```
python potapy.app
```

Access the web console:

```
http://127.0.0.1:8050/
```

### Activator Log

Shows basic info about activations:
- Total Activations
- Total QSOs
- Attempts vs Success
- Avg QSOs per Activation
- Total Parks Activated

Also includes a map that shows activated parks with stats (may not always be able to locate the park to put on the map - will show as failed to locate below the map)

### Hunter Log

Shows basic info about hunts:
- Total hunter QSOs
- Total Parks Hunted
- Most Common US States Hunted (app assumes you are in US)
- Most Common DX Countries Hunted (app assumes you are in US)

Same as Activator, shows a map of hunted parks, along with same issue of not loading all parks on the map



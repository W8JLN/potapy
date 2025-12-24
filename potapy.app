import dash
from dash import dcc, html, Input, Output, State
import pandas as pd
import plotly.express as px
from io import StringIO
import base64
from geopy.geocoders import Nominatim
from geopy.extra.rate_limiter import RateLimiter
import time
import dash_bootstrap_components as dbc

# Initialize geocoder
geolocator = Nominatim(user_agent="pota_dashboard")
geocode = RateLimiter(geolocator.geocode, min_delay_seconds=1, error_wait_seconds=2)
geocode_cache = {}

app = dash.Dash(__name__, external_stylesheets=[dbc.themes.BOOTSTRAP])
app.title = "POTA Dashboard"


def geocode_parks(parks, countries=None):
    latitudes, longitudes, failed = [], [], []

    for i, park in enumerate(parks):
        query = park
        if countries is not None and i < len(countries):
            query += f", {countries[i]}"

        if query in geocode_cache:
            location = geocode_cache[query]
        else:
            try:
                location = geocode(query)
                geocode_cache[query] = location
            except:
                location = None

        if location:
            latitudes.append(location.latitude)
            longitudes.append(location.longitude)
        else:
            latitudes.append(None)
            longitudes.append(None)
            failed.append(park)

        time.sleep(1)

    return latitudes, longitudes, failed


def create_summary_card(title, value, color="primary", icon=None):
    icon_elem = html.I(className=f"bi bi-{icon} me-2") if icon else None

    return dbc.Col(
        dbc.Card(
            dbc.CardBody([
                html.H5([icon_elem, title], className="card-title"),
                html.H2(value, className=f"text-{color} fw-bold")
            ]),
            className="shadow-sm mb-3"
        ),
        width=2
    )


app.layout = dbc.Container([
    dbc.Row([
        dbc.Col(
            html.H1("POTA Dashboard", id="dashboard-title"),
            width=12,
            className="my-4 text-center"
        )
    ]),

    dbc.Row([
        dbc.Col([
            dbc.Label("Step 1: Enter Your Call Sign"),
            dcc.Input(
                id="callsign-input",
                type="text",
                placeholder="e.g. K0ABC",
                className="form-control"
            ),
        ], width=4),
    ], className="mb-3 justify-content-center"),

    dbc.Row([
        dbc.Col([
            dbc.Label("Step 2: Select Log Type"),
            dbc.RadioItems(
                id="log-type",
                options=[
                    {"label": "Activator Log", "value": "activator"},
                    {"label": "Hunter Log", "value": "hunter"},
                ],
                value=None,
                inline=True
            ),
        ], width=4),
    ], className="mb-3 justify-content-center"),

    dbc.Row([
        dbc.Col([
            dbc.Label("Step 3: Upload Your CSV"),
            dcc.Upload(
                id="upload-data",
                children=html.Div([
                    "Drag and Drop or ",
                    html.A("Select Files")
                ]),
                style={
                    "width": "100%",
                    "height": "60px",
                    "lineHeight": "60px",
                    "borderWidth": "1px",
                    "borderStyle": "dashed",
                    "borderRadius": "5px",
                    "textAlign": "center",
                    "cursor": "pointer",
                    "color": "#555"
                },
                multiple=False,
                disabled=True
            ),
        ], width=6),
    ], className="mb-4 justify-content-center"),

    dcc.Loading(
        id="loading-wrapper",
        type="circle",
        fullscreen=True,
        children=html.Div(
            id="dashboard-content",
            style={"display": "none"}
        )
    )
], fluid=True)


@app.callback(
    Output("upload-data", "disabled"),
    Input("callsign-input", "value"),
    Input("log-type", "value")
)
def enable_upload(callsign, log_type):
    return not (callsign and log_type)


@app.callback(
    Output("dashboard-title", "children"),
    Output("dashboard-content", "children"),
    Output("dashboard-content", "style"),
    Input("upload-data", "contents"),
    State("upload-data", "filename"),
    State("callsign-input", "value"),
    State("log-type", "value"),
    prevent_initial_call=True
)
def update_dashboard(contents, filename, callsign, log_type):
    if contents is None or not callsign or not log_type:
        return "POTA Dashboard", [], {"display": "none"}

    # Parse CSV content
    content_type, content_string = contents.split(",")
    decoded = StringIO(base64.b64decode(content_string).decode("utf-8"))
    df = pd.read_csv(decoded)

    countries = df.get("DX Entity", None)
    latitudes, longitudes, failed_parks = geocode_parks(
        df["Park Name"].tolist(),
        countries
    )

    df["Latitude"] = latitudes
    df["Longitude"] = longitudes
    df_map = df.dropna(subset=["Latitude", "Longitude"])

    if log_type == "activator":
        total_activations = df["Activations"].sum() if "Activations" in df.columns else 0
        total_qsos = df["QSOs"].sum() if "QSOs" in df.columns else 0
        total_attempts = df["Attempts"].sum() if "Attempts" in df.columns else total_activations
        failed_activations = total_attempts - total_activations
        avg_qsos_per_activation = (
            round(total_qsos / total_activations, 2)
            if total_activations else 0
        )
        total_parks = df["Park Name"].nunique()

        cards = dbc.Row([
            create_summary_card("Total Activations", total_activations, "success", "check-circle"),
            create_summary_card("Total QSOs", total_qsos, "info", "antenna"),
            create_summary_card(
                "Attempts vs Success",
                f"Success: {total_activations}, Failed: {failed_activations}",
                "warning",
                "bar-chart"
            ),
            create_summary_card("Avg QSOs per Activation", avg_qsos_per_activation, "primary", "graph-up"),
            create_summary_card("Total Parks Activated", total_parks, "secondary", "geo-alt"),
        ], justify="around")

        # NEW: Parks Activated graph (most → least)
        park_activation_df = (
            df.groupby("Park Name", as_index=False)["Activations"]
            .sum()
            .sort_values("Activations", ascending=True)
        )

        attempts_success_fig = px.bar(
            park_activation_df,
            x="Activations",
            y="Park Name",
            orientation="h",
            text="Activations",
            title="Parks Activated (Most → Least)",
            labels={"Activations": "# Activations", "Park Name": "Park"}
        )

        attempts_success_fig.update_traces(textposition="outside")
        attempts_success_fig.update_layout(
            margin=dict(l=0, r=20, t=40, b=40),
            yaxis={"categoryorder": "total ascending"}
        )

        qsos_per_park_fig = px.bar(
            df.sort_values("QSOs", ascending=True),
            x="QSOs",
            y="Park Name",
            orientation="h",
            text="QSOs",
            title="QSOs per Park",
            labels={"QSOs": "QSOs", "Park Name": "Park"}
        )

        qsos_per_park_fig.update_traces(textposition="outside")
        qsos_per_park_fig.update_layout(
            margin=dict(l=0, r=20, t=40, b=40),
            yaxis={"categoryorder": "total ascending"}
        )

    else:
        total_qsos = df["QSOs"].sum() if "QSOs" in df.columns else 0
        total_parks = df["Park Name"].nunique()

        cards = dbc.Row([
            create_summary_card("Total QSOs", total_qsos, "info", "antenna"),
            create_summary_card("Total Parks Contacted", total_parks, "secondary", "geo-alt"),
        ], justify="start")

        # Define US DX Entity name exactly
        us_name = "United States of America"

        # Filter US rows (assumed user country)
        us_df = df[df["DX Entity"] == us_name]

        us_state_df = (
            us_df.groupby("Location", as_index=False)["QSOs"]
            .sum()
            .sort_values("QSOs", ascending=True)
        )

        us_state_fig = px.bar(
            us_state_df,
            x="QSOs",
            y="Location",
            orientation="h",
            text="QSOs",
            title="Most Common US States Hunted",
            labels={"QSOs": "QSOs", "Location": "US State"}
        )

        us_state_fig.update_traces(textposition="outside")
        us_state_fig.update_layout(
            margin=dict(l=0, r=20, t=40, b=40),
            yaxis={"categoryorder": "total ascending"}
        )

        # DX Countries excluding US (assume US user)
        dx_df = df[df["DX Entity"] != us_name]

        dx_country_df = (
            dx_df.groupby("DX Entity", as_index=False)["QSOs"]
            .sum()
            .sort_values("QSOs", ascending=True)
        )

        dx_country_fig = px.bar(
            dx_country_df,
            x="QSOs",
            y="DX Entity",
            orientation="h",
            text="QSOs",
            title="Most Common DX Countries Hunted",
            labels={"QSOs": "QSOs", "DX Entity": "Country"}
        )

        dx_country_fig.update_traces(textposition="outside")
        dx_country_fig.update_layout(
            margin=dict(l=0, r=20, t=40, b=40),
            yaxis={"categoryorder": "total ascending"}
        )

        # Most commonly hunted parks
        park_df = (
            df.groupby(["Reference", "Park Name"], as_index=False)["QSOs"]
            .sum()
            .sort_values("QSOs", ascending=True)
        )

        park_df["Park"] = park_df["Park Name"] + " (" + park_df["Reference"] + ")"

        park_fig = px.bar(
            park_df,
            x="QSOs",
            y="Park",
            orientation="h",
            text="QSOs",
            title="Most Commonly Hunted Parks",
            labels={"QSOs": "QSOs", "Park": "Park"}
        )

        park_fig.update_traces(textposition="outside")
        park_fig.update_layout(
            margin=dict(l=0, r=20, t=40, b=40),
            yaxis={"categoryorder": "total ascending"}
        )

        attempts_success_fig = None
        qsos_per_park_fig = None

    map_fig = px.scatter_mapbox(
        df_map,
        lat="Latitude",
        lon="Longitude",
        hover_name="Park Name",
        hover_data={"Activations": True, "Attempts": True, "QSOs": True}
        if log_type == "activator" else {"QSOs": True},
        size="QSOs",
        color="Activations"
        if log_type == "activator" and "Activations" in df_map.columns else None,
        color_continuous_scale="Viridis" if log_type == "activator" else None,
        zoom=2,
        height=600
    )

    map_fig.update_layout(mapbox_style="open-street-map")
    map_fig.update_layout(margin={"r": 0, "t": 0, "l": 0, "b": 0})

    failed_list_items = [html.Li(park) for park in failed_parks]

    children = [
        cards,
        dbc.Row([
            dbc.Col(
                dcc.Graph(
                    id="attempts-success-graph",
                    figure=attempts_success_fig
                ) if attempts_success_fig else html.Div(),
                width=6
            ),
            dbc.Col(
                dcc.Graph(
                    id="qsos-per-park-graph",
                    figure=qsos_per_park_fig
                ) if qsos_per_park_fig else html.Div(),
                width=6
            )
        ]),
    ]

    # Add hunter log extra graphs only if hunter
    if log_type == "hunter":
        children += [
            dbc.Row([
                dbc.Col(dcc.Graph(figure=us_state_fig), width=6),
                dbc.Col(dcc.Graph(figure=dx_country_fig), width=6),
            ]),
            dbc.Row([
                dbc.Col(dcc.Graph(figure=park_fig), width=12),
            ]),
        ]

    children += [
        dbc.Row([
            dbc.Col(dcc.Graph(id="map-graph", figure=map_fig), width=12)
        ]),
        dbc.Row([
            dbc.Col(html.H4("Parks Failed to Geocode:"), width=12)
        ]),
        dbc.Row([
            dbc.Col(html.Ul(failed_list_items), width=12)
        ])
    ]

    return (
        f"POTA Dashboard for {callsign} ({log_type.capitalize()} Log)",
        children,
        {"display": "block"}
    )


if __name__ == "__main__":
    app.run(debug=True)

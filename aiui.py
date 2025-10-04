import streamlit as st
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import pymysql
import pathlib
import datetime as dt

#Google Map API

import streamlit as st
import streamlit.components.v1 as components




#比率調整　EC2とローカル

st.set_page_config(
    page_title="わいの四柱推命",   # ← ページのタイトル（タブ名に出ます）
    layout="wide",             # ← 画面いっぱいに広げる
    initial_sidebar_state="expanded"  # ← サイドバー展開状態も指定可
)


#わいの四柱推命
st.image("banner.png", use_container_width=True)


# -------------------------------------------------
# DB接続
# -------------------------------------------------
conn = pymysql.connect(
    host="database-2.c9gmi6sy8xzv.ap-northeast-3.rds.amazonaws.com",
    port=3306,
    user="ymori",
    password="Mori1019",
    database="shichusuimei",
    charset="utf8mb4",
    cursorclass=pymysql.cursors.DictCursor
)

# -------------------------------------------------
# SQL読込
# -------------------------------------------------
def load_sql(name: str) -> str:
    base = pathlib.Path(__file__).resolve().parent
    path = base / name
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

sql_info   = load_sql("sql_info.sql")
sql_daiyun = load_sql("sql_daiyun.sql")
sql_nenun  = load_sql("sql_nenun.sql")

# ====== 見た目 ======
st.markdown("""
<style>
.block-container{max-width:1300px;margin:auto;}
table{border-collapse:collapse;width:100%;}
th,td{border:1px solid #ddd;text-align:center;padding:4px;}
:root{ --daiun-label-top: 34px; }
.daiun-side-label{ margin-top: var(--daiun-label-top); font-weight:700; }
</style>
""", unsafe_allow_html=True)

# ====== 入力 ======

st.subheader("入力")
row1 = st.columns([1,0.8,0.8,0.8,0.8,0.8,0.6,1])
with row1[0]: name  = st.text_input("名前")
with row1[1]: year  = st.number_input("年", 1900, 2100, 1977)
with row1[2]: month = st.number_input("月", 1, 12, 10)
with row1[3]: day   = st.number_input("日", 1, 31, 19)
with row1[4]: hour  = st.number_input("時", 0, 23, 9)
with row1[5]: minute = st.number_input("分", 0, 59, 45)
with row1[6]: gender = st.radio("性別", ["  男性"," 女性"])
with row1[7]: show_map = st.button("出生地を表示", key="map_button")

b1, b2, b3, b4 ,b5 , b6 ,b7 , b8 = st.columns(8) 

# ボタン押したときに地図を表示する


if show_map:
    html_code = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Map Click Coordinates</title>
        <style>
        #map {
            height: 500px;
            width: 100%;
        }
        </style>
        <script>
        function initMap() {
            const map = new google.maps.Map(document.getElementById("map"), {
            center: { lat: 35.6812, lng: 139.7671 }, // 東京駅
            zoom: 10,
            });

            const marker = new google.maps.Marker({
            position: { lat: 35.6812, lng: 139.7671 },
            map: map,
            title: "選択地点"
            });

            map.addListener("click", (e) => {
            const lat = e.latLng.lat().toFixed(6);
            const lng = e.latLng.lng().toFixed(6);
            marker.setPosition(e.latLng);
            document.getElementById("coords").innerText = `緯度: ${lat}, 経度: ${lng}`;
            });
        }

        window.initMap = initMap;
        </script>
    </head>
    <body>
        <div id="map"></div>
        <p id="coords" style="margin-top:10px; font-size:16px;">地図をクリックしてください</p>
        <script async
        src="https://maps.googleapis.com/maps/api/js?key=YOUR_API_KEY&callback=initMap">
        </script>
    </body>
    </html>
    """

    # APIキーを埋め込む
    html_code = html_code.replace("YOUR_API_KEY", "AIzaSyD1nGnn98TvKSuwxDvTWoebyZg1kV1oLio")
    components.html(html_code, height=600)

with b4:
    run_btn = st.button("実行")
with b5:
    st.button("クリア")

# ====== 区切り ======
st.markdown("---")

# ====== データ準備（実行前は🈳を表示） ======
df_meishiki = pd.DataFrame({
    "項目": ["干支番号","通変星","天干","地支","冲・合・刑","蔵干の五行","蔵干","蔵干通変星",
           "十二運","空亡","伏吟","天同地冲","天地徳合","天剋地冲","宿命大半会","神殺"],
    "時柱": ["🈳"]*16,
    "日柱": ["🈳"]*16,
    "月柱": ["🈳"]*16,
    "年柱": ["🈳"]*16
})

df_daiun = pd.DataFrame({
    "年":["🈳"]*10,
    "月":["🈳"]*10,
    "干支":["🈳"]*10,
    "十神":["🈳"]*10,
    "運勢":["🈳"]*10
})

df_nenun = pd.DataFrame({
    "年":["🈳"]*5,
    "干支":["🈳"]*5,
    "十神":["🈳"]*5,
    "運勢":["🈳"]*5
})

df_tenkan = pd.DataFrame({"項目":["十神","五行","天干","地支","合計"], "値":["●","●","●","●","●"]})
df_kekka  = pd.DataFrame({"項目":["格局","喜神","忌神","調候用神"], "値":["●","●","●","●"]})

# ====== 実行ボタンでSQL発火 ======
if run_btn:
    try:
        # 出生日時の組み立てと時差補正
        birth_dt     = dt.datetime(year, month, day, hour, minute)
        birth_dt_adj = birth_dt + dt.timedelta(minutes=0)  # jisa_variant=0 の仮実装
        birth_dt_str = birth_dt_adj.strftime("%Y-%m-%d %H:%M")
        gender_code  = "M" if gender == "男性" else "F"

        cur = conn.cursor()

        # 命式
        cur.execute(sql_info, (birth_dt_str, gender_code))
        rows_info = cur.fetchall()
        df_meishiki = pd.DataFrame(rows_info) if rows_info else df_meishiki

        # 大運
        cur.execute(sql_daiyun, (birth_dt_str, gender_code))
        rows_daiun = cur.fetchall()
        df_daiun = pd.DataFrame(rows_daiun) if rows_daiun else df_daiun

        # 年運
        y_from = dt.date.today().year
        y_to   = y_from + 4
        cur.execute(sql_nenun, (birth_dt_str, gender_code, y_from, y_to))
        rows_nenun = cur.fetchall()
        df_nenun = pd.DataFrame(rows_nenun) if rows_nenun else df_nenun

        #　格局・喜神・忌神
        choko   = df_meishiki.loc[df_meishiki['項目']=="調候用神","日柱"].values[0] 
        df_kekka  = pd.DataFrame({"項目":["格局","喜神","忌神","調候用神"], "値":["●","●","●",choko]})

    except Exception as e:
        st.error(f"SQL実行エラー: {e}")

# ====== 命式（左）・大運＋年運（右） ======
block = st.container()
with block:
    L2, R2 = st.columns([2,2])

    with L2:
        st.subheader("命式")
        st.table(df_meishiki)

    with R2:
        st.subheader("大運")
        st.table(df_daiun)
        st.subheader("年運")
        st.table(df_nenun)

# ====== 区切り ======
st.markdown("---")

# ====== 残り：十神・五行 / 格局・喜神・忌神 / 宇宙盤 / 五行バランス ======
B1, B2 = st.columns([2,2])

with B1:
    st.subheader("十神・五行")
    st.table(df_tenkan)
    st.subheader("格局・喜神・忌神")
    st.table(df_kekka)

with B2:
    st.subheader("宇宙盤")

    if not df_meishiki.empty:
        try:
            # 🈳や60の補正
            def convert_value(val, kind):
                if val == "🈳":
                    if kind == "日柱": return 20
                    if kind == "月柱": return 40
                    if kind == "年柱": return 0
                try:
                    num = int(val)
                    return 0 if num == 60 else num
                except (ValueError, TypeError):
                    return None

            day_num   = convert_value(df_meishiki.loc[df_meishiki['項目']=="干支番号","日柱"].values[0], "日柱")
            month_num = convert_value(df_meishiki.loc[df_meishiki['項目']=="干支番号","月柱"].values[0], "月柱")
            year_num  = convert_value(df_meishiki.loc[df_meishiki['項目']=="干支番号","年柱"].values[0], "年柱")

            points = [p for p in [day_num, month_num, year_num] if p is not None]

            fig, ax = plt.subplots(figsize=(4,4))
            circle = plt.Circle((0,0), 1, color="black", fill=False)
            ax.add_artist(circle)

            xs, ys = [], []
            for n in points:
                # 時計回り & 6時を基準
                ang = -((n % 60) / 60) * 2 * np.pi - (np.pi/2)
                x, y = np.cos(ang), np.sin(ang)
                xs.append(x); ys.append(y)
                ax.text(x*1.12, y*1.12, str(n), ha="center", va="center", fontsize=9)

            if len(xs) > 1:
                xs.append(xs[0]); ys.append(ys[0])
                ax.plot(xs, ys, color="red", linewidth=2)

            ax.set_xlim(-1.15,1.15); ax.set_ylim(-1.15,1.15)
            ax.set_aspect("equal"); ax.axis("off")
            st.pyplot(fig, use_container_width=False, bbox_inches="tight")

        except Exception as e:
            st.error(f"宇宙盤の描画エラー: {e}")


st.subheader("五行バランス")
W = st.columns(5)
labels = ["水","木","火","土","金"]
colors = ["#00BFFF","#90EE90","#FF6347","#DAA520","#D3D3D3"]
for c, lab, col in zip(W, labels, colors):
    c.markdown(f"<div style='background:{col};padding:20px;text-align:center;'>{lab}</div>", unsafe_allow_html=True)

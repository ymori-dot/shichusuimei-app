WITH RECURSIVE
params AS (
  SELECT STR_TO_DATE(%s,'%%Y-%%m-%%d %%H:%%i') AS birth_dt, %s AS gender
),

-- 年/月/日 通番（年は立春前=前年扱い）
yearpillar AS (
  SELECT MOD((YEAR(p.birth_dt) - CASE
           WHEN p.birth_dt < (
             SELECT STR_TO_DATE(CONCAT(s.date,' ',s.time),'%%Y-%%m-%%d %%H:%%i')
             FROM sekki s
             WHERE MOD(s.id,2)=1 AND s.name LIKE '立春%%'
               AND YEAR(STR_TO_DATE(CONCAT(s.date,' ',s.time),'%%Y-%%m-%%d %%H:%%i')) = YEAR(p.birth_dt)
             ORDER BY STR_TO_DATE(CONCAT(s.date,' ',s.time),'%%Y-%%m-%%d %%H:%%i')
             LIMIT 1
           ) THEN 1925 ELSE 1924 END)+60,60) AS 年柱通番
  FROM params p
),
monthpillar AS (
  SELECT MOD(
           (
             ((YEAR(p.birth_dt)-1923)*12 + (MONTH(p.birth_dt)-12)) +
             CASE WHEN p.birth_dt < (
                    SELECT MIN(STR_TO_DATE(CONCAT(s.date,' ',s.time),'%%Y-%%m-%%d %%H:%%i'))
                    FROM sekki s
                    WHERE MOD(s.id,2)=1
                      AND YEAR(STR_TO_DATE(CONCAT(s.date,' ',s.time),'%%Y-%%m-%%d %%H:%%i'))=YEAR(p.birth_dt)
                      AND MONTH(STR_TO_DATE(CONCAT(s.date,' ',s.time),'%%Y-%%m-%%d %%H:%%i'))=MONTH(p.birth_dt)
                  ) THEN -1 ELSE 0 END
           ) + 60, 60
         ) AS 月柱通番
  FROM params p
),
daypillar AS (
  SELECT MOD(TIMESTAMPDIFF(DAY,'1916-03-28',p.birth_dt),60) AS 日柱通番
  FROM params p
),

-- 基本（年干・日干・順逆）
base AS (
  SELECT
    p.birth_dt, p.gender,
    y.年柱通番, m.月柱通番, d.日柱通番,
    ey.tenkan AS 年干, ed.tenkan AS 日干,
    CASE
      WHEN p.gender='M' AND ey.tenkan IN ('乙','丁','己','辛','癸') THEN '逆運'
      WHEN p.gender='M' AND ey.tenkan IN ('甲','丙','戊','庚','壬') THEN '順運'
      WHEN p.gender='F' AND ey.tenkan IN ('乙','丁','己','辛','癸') THEN '順運'
      WHEN p.gender='F' AND ey.tenkan IN ('甲','丙','戊','庚','壬') THEN '逆運'
    END AS dir
  FROM params p
  JOIN yearpillar y ON 1=1
  JOIN monthpillar m ON 1=1
  JOIN daypillar d ON 1=1
  LEFT JOIN eto60 ey ON ey.id = y.年柱通番
  LEFT JOIN eto60 ed ON ed.id = d.日柱通番
),

-- 立運（日数差用の節気）
sekki_fixed AS (
  SELECT STR_TO_DATE(CONCAT(s.date,' ',s.time),'%%Y-%%m-%%d %%H:%%i') AS s_dt, s.name
  FROM sekki s WHERE MOD(s.id,2)=1
),
prev_sekki AS (
  SELECT sf.s_dt FROM sekki_fixed sf, params p
  WHERE sf.s_dt < p.birth_dt ORDER BY sf.s_dt DESC LIMIT 1
),
next_sekki AS (
  SELECT sf.s_dt FROM sekki_fixed sf, params p
  WHERE sf.s_dt > p.birth_dt ORDER BY sf.s_dt ASC LIMIT 1
),

-- 立運の年数・月数
liyun_nm AS (
  SELECT
    b.*,
    CASE WHEN b.dir='順運'
         THEN TIMESTAMPDIFF(DAY, b.birth_dt, (SELECT n.s_dt FROM next_sekki n))
         ELSE TIMESTAMPDIFF(DAY, (SELECT v.s_dt FROM prev_sekki v), b.birth_dt)
    END AS diff_days,
    FLOOR( CASE WHEN b.dir='順運'
                THEN TIMESTAMPDIFF(DAY, b.birth_dt, (SELECT n.s_dt FROM next_sekki n))
                ELSE TIMESTAMPDIFF(DAY, (SELECT v.s_dt FROM prev_sekki v), b.birth_dt)
           END / 3 ) AS 立運年数,
    ROUND(
      (
        CASE WHEN b.dir='順運'
             THEN TIMESTAMPDIFF(DAY, b.birth_dt, (SELECT n.s_dt FROM next_sekki n))
             ELSE TIMESTAMPDIFF(DAY, (SELECT v.s_dt FROM prev_sekki v), b.birth_dt)
        END
        - (FLOOR(
             CASE WHEN b.dir='順運'
                  THEN TIMESTAMPDIFF(DAY, b.birth_dt, (SELECT n.s_dt FROM next_sekki n))
                  ELSE TIMESTAMPDIFF(DAY, (SELECT v.s_dt FROM prev_sekki v), b.birth_dt)
             END / 3
           ) * 3)
      ) * 4, 0
    ) AS 立運月数
  FROM base b
),
start_nm AS (
  SELECT
    l.*,
    YEAR(l.birth_dt) + l.立運年数
      + FLOOR( (MONTH(l.birth_dt)-1 + l.立運月数)/12 ) AS start_year,
    MOD((MONTH(l.birth_dt)-1 + l.立運月数),12) + 1       AS start_month
  FROM liyun_nm l
),

-- ★予約語を避ける：rows -> dai_rows
dai_rows AS (
  -- 行1：生年・生月（干支＝月柱通番）
  SELECT
    1 AS rownum,
    YEAR(s.birth_dt)  AS year_val,
    MONTH(s.birth_dt) AS month_val,
    s.月柱通番        AS eto_idx,
    s.日干            AS day_master,
    s.dir
  FROM start_nm s

  UNION ALL

  -- 行2〜11：10年刻み／順運=+1, 逆運=-1 で干支を回す
  SELECT
    r.rownum + 1,
    CASE WHEN r.rownum=1 THEN s.start_year  ELSE r.year_val + 10 END,
    CASE WHEN r.rownum=1 THEN s.start_month ELSE r.month_val     END,
    CASE WHEN r.dir='順運' THEN MOD(r.eto_idx + 1 + 60, 60)
                            ELSE MOD(r.eto_idx - 1 + 60, 60) END,
    r.day_master,
    r.dir
  FROM dai_rows r
  JOIN start_nm s ON 1=1
  WHERE r.rownum < 11
)

SELECT
  r.year_val  AS 運年,
  r.month_val AS 運月,
  e.eto AS 年干支,
  t.star      AS 通変星,   -- 日干 × 大運天干
  j.unsei     AS 十二運    -- 日干 × 大運地支
FROM dai_rows r
LEFT JOIN eto60     e ON e.id = r.eto_idx
LEFT JOIN tsuhensei t ON t.nikkan = r.day_master AND t.target = e.tenkan
LEFT JOIN juniun    j ON j.nikkan = r.day_master AND j.chishi = e.chishi
ORDER BY r.rownum;
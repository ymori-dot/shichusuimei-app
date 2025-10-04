WITH
params AS (
  SELECT
    STR_TO_DATE(%s,'%%Y-%%m-%%d %%H:%%i') AS birth_dt,
    %s AS gender
),

-- 節気（奇数id=節入り）をDATETIME化
sekki_fixed AS (
  SELECT
    s.id,
    STR_TO_DATE(CONCAT(s.date,' ',s.time),'%%Y-%%m-%%d %%H:%%i') AS s_dt,
    s.name
  FROM sekki s
  WHERE MOD(s.id,2)=1
),

-- 誕生直前/直後の節気
prev_sekki AS (
  SELECT s.s_dt, CONCAT(DATE_FORMAT(s.s_dt,'%%Y-%%m-%%d %%H:%%i'),' ',s.name) AS label
  FROM sekki_fixed s, params p
  WHERE s.s_dt < p.birth_dt
  ORDER BY s.s_dt DESC LIMIT 1
),
next_sekki AS (
  SELECT s.s_dt, CONCAT(DATE_FORMAT(s.s_dt,'%%Y-%%m-%%d %%H:%%i'),' ',s.name) AS label
  FROM sekki_fixed s, params p
  WHERE s.s_dt > p.birth_dt
  ORDER BY s.s_dt ASC LIMIT 1
),

-- 当年の立春
risshun AS (
  SELECT s.s_dt AS risshun_dt
  FROM sekki_fixed s, params p
  WHERE s.name LIKE '立春%%'
    AND YEAR(s.s_dt)=YEAR(p.birth_dt)
  ORDER BY s.s_dt ASC
  LIMIT 1
),

-- 年/月/日 通番（0-59）
yearpillar AS (
  SELECT MOD((YEAR(p.birth_dt) -
              CASE WHEN p.birth_dt < (SELECT r.risshun_dt FROM risshun r) THEN 1925 ELSE 1924 END
             )+60,60) AS 年柱通番
  FROM params p
),
monthpillar AS (
  SELECT MOD( (((YEAR(p.birth_dt)-1923)*12 + (MONTH(p.birth_dt)-12))
               + CASE
                   WHEN p.birth_dt < (
                     SELECT MIN(s.s_dt) FROM sekki_fixed s
                     WHERE YEAR(s.s_dt)=YEAR(p.birth_dt) AND MONTH(s.s_dt)=MONTH(p.birth_dt)
                   ) THEN -1 ELSE 0
                 END
               + 60), 60) AS 月柱通番
  FROM params p
),
daypillar AS (
  SELECT MOD(TIMESTAMPDIFF(DAY,'1916-03-28',p.birth_dt),60) AS 日柱通番
  FROM params p
),

-- 基本（干支/干支文字/順逆）
base AS (
  SELECT
    p.birth_dt, p.gender,
    y.年柱通番, m.月柱通番, d.日柱通番,
    ey.eto AS 年柱干支, em.eto AS 月柱干支, ed.eto AS 日柱干支,
    ey.tenkan AS 年干, em.tenkan AS 月干, ed.tenkan AS 日干,
    ey.chishi AS 年支, em.chishi AS 月支, ed.chishi AS 日支,
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
  LEFT JOIN eto60 ey ON ey.id=y.年柱通番
  LEFT JOIN eto60 em ON em.id=m.月柱通番
  LEFT JOIN eto60 ed ON ed.id=d.日柱通番
),

-- 時支（2時間刻み）
jishi AS (
  SELECT p.birth_dt,
         CASE HOUR(p.birth_dt)
           WHEN 23 THEN '子' WHEN 0 THEN '子'
           WHEN 1 THEN '丑' WHEN 2 THEN '丑'
           WHEN 3 THEN '寅' WHEN 4 THEN '寅'
           WHEN 5 THEN '卯' WHEN 6 THEN '卯'
           WHEN 7 THEN '辰' WHEN 8 THEN '辰'
           WHEN 9 THEN '巳' WHEN 10 THEN '巳'
           WHEN 11 THEN '午' WHEN 12 THEN '午'
           WHEN 13 THEN '未' WHEN 14 THEN '未'
           WHEN 15 THEN '申' WHEN 16 THEN '申'
           WHEN 17 THEN '酉' WHEN 18 THEN '酉'
           WHEN 19 THEN '戌' WHEN 20 THEN '戌'
           WHEN 21 THEN '亥' WHEN 22 THEN '亥'
         END AS 時支
  FROM params p
),

-- 時柱干支
timepillar AS (
  SELECT j.birth_dt,
         CONCAT(jj.jikkan,j.時支) AS 時柱干支,
         jj.jikkan AS 時干
  FROM jishi j
  JOIN base b ON b.birth_dt=j.birth_dt
  JOIN jikkan_jishi jj ON jj.nikkan=b.日干 AND jj.jishi=j.時支
),

-- 蔵干 / 五行 / 通変星
zstar AS (
  SELECT b.birth_dt,
         zy.zoukan AS 年蔵干, zm.zoukan AS 月蔵干, zd.zoukan AS 日蔵干, zt.zoukan AS 時蔵干,
         gy1.gogyo AS 年五1, gm1.gogyo AS 月五1, gd1.gogyo AS 日五1, gt1.gogyo AS 時五1,
         ty1.star AS 年星1, tm1.star AS 月星1, td1.star AS 日星1, tt1.star AS 時星1,
         gy2.gogyo AS 年五2, gm2.gogyo AS 月五2, gd2.gogyo AS 日五2, gt2.gogyo AS 時五2,
         ty2.star AS 年星2, tm2.star AS 月星2, td2.star AS 日星2, tt2.star AS 時星2,
         gy3.gogyo AS 年五3, gm3.gogyo AS 月五3, gd3.gogyo AS 日五3, gt3.gogyo AS 時五3,
         ty3.star AS 年星3, tm3.star AS 月星3, td3.star AS 日星3, tt3.star AS 時星3
  FROM base b
  LEFT JOIN jishi j   ON j.birth_dt=b.birth_dt
  LEFT JOIN zoukan zy ON zy.tisi=b.年支
  LEFT JOIN zoukan zm ON zm.tisi=b.月支
  LEFT JOIN zoukan zd ON zd.tisi=b.日支
  LEFT JOIN zoukan zt ON zt.tisi=j.時支
  LEFT JOIN zoukan_gogyo gy1 ON gy1.tenkan=SUBSTRING(zy.zoukan,1,1)
  LEFT JOIN zoukan_gogyo gy2 ON gy2.tenkan=SUBSTRING(zy.zoukan,2,1)
  LEFT JOIN zoukan_gogyo gy3 ON gy3.tenkan=SUBSTRING(zy.zoukan,3,1)
  LEFT JOIN zoukan_gogyo gm1 ON gm1.tenkan=SUBSTRING(zm.zoukan,1,1)
  LEFT JOIN zoukan_gogyo gm2 ON gm2.tenkan=SUBSTRING(zm.zoukan,2,1)
  LEFT JOIN zoukan_gogyo gm3 ON gm3.tenkan=SUBSTRING(zm.zoukan,3,1)
  LEFT JOIN zoukan_gogyo gd1 ON gd1.tenkan=SUBSTRING(zd.zoukan,1,1)
  LEFT JOIN zoukan_gogyo gd2 ON gd2.tenkan=SUBSTRING(zd.zoukan,2,1)
  LEFT JOIN zoukan_gogyo gd3 ON gd3.tenkan=SUBSTRING(zd.zoukan,3,1)
  LEFT JOIN zoukan_gogyo gt1 ON gt1.tenkan=SUBSTRING(zt.zoukan,1,1)
  LEFT JOIN zoukan_gogyo gt2 ON gt2.tenkan=SUBSTRING(zt.zoukan,2,1)
  LEFT JOIN zoukan_gogyo gt3 ON gt3.tenkan=SUBSTRING(zt.zoukan,3,1)
  LEFT JOIN tsuhensei ty1 ON ty1.nikkan=b.日干 AND ty1.target=SUBSTRING(zy.zoukan,1,1)
  LEFT JOIN tsuhensei ty2 ON ty2.nikkan=b.日干 AND ty2.target=SUBSTRING(zy.zoukan,2,1)
  LEFT JOIN tsuhensei ty3 ON ty3.nikkan=b.日干 AND ty3.target=SUBSTRING(zy.zoukan,3,1)
  LEFT JOIN tsuhensei tm1 ON tm1.nikkan=b.日干 AND tm1.target=SUBSTRING(zm.zoukan,1,1)
  LEFT JOIN tsuhensei tm2 ON tm2.nikkan=b.日干 AND tm2.target=SUBSTRING(zm.zoukan,2,1)
  LEFT JOIN tsuhensei tm3 ON tm3.nikkan=b.日干 AND tm3.target=SUBSTRING(zm.zoukan,3,1)
  LEFT JOIN tsuhensei td1 ON td1.nikkan=b.日干 AND td1.target=SUBSTRING(zd.zoukan,1,1)
  LEFT JOIN tsuhensei td2 ON td2.nikkan=b.日干 AND td2.target=SUBSTRING(zd.zoukan,2,1)
  LEFT JOIN tsuhensei td3 ON td3.nikkan=b.日干 AND td3.target=SUBSTRING(zd.zoukan,3,1)
  LEFT JOIN tsuhensei tt1 ON tt1.nikkan=b.日干 AND tt1.target=SUBSTRING(zt.zoukan,1,1)
  LEFT JOIN tsuhensei tt2 ON tt2.nikkan=b.日干 AND tt2.target=SUBSTRING(zt.zoukan,2,1)
  LEFT JOIN tsuhensei tt3 ON tt3.nikkan=b.日干 AND tt3.target=SUBSTRING(zt.zoukan,3,1)
),

-- 空亡
kuubou_map AS (
  SELECT b.birth_dt,
         ky.kuubou AS 年空亡, km.kuubou AS 月空亡, kd.kuubou AS 日空亡, kt.kuubou AS 時空亡
  FROM base b
  LEFT JOIN timepillar tp ON tp.birth_dt=b.birth_dt
  LEFT JOIN kuubou ky ON ky.tenkantisi=b.年柱干支
  LEFT JOIN kuubou km ON km.tenkantisi=b.月柱干支
  LEFT JOIN kuubou kd ON kd.tenkantisi=b.日柱干支
  LEFT JOIN kuubou kt ON kt.tenkantisi=tp.時柱干支
),

-- 十二運
juniun_map AS (
  SELECT b.birth_dt,
         ju1.unsei AS 年十二運,
         ju2.unsei AS 月十二運,
         ju3.unsei AS 日十二運,
         ju4.unsei AS 時十二運
  FROM base b
  LEFT JOIN jishi j    ON j.birth_dt=b.birth_dt
  LEFT JOIN timepillar tp ON tp.birth_dt=b.birth_dt
  LEFT JOIN juniun ju1 ON ju1.nikkan=b.日干 AND ju1.chishi=b.年支
  LEFT JOIN juniun ju2 ON ju2.nikkan=b.日干 AND ju2.chishi=b.月支
  LEFT JOIN juniun ju3 ON ju3.nikkan=b.日干 AND ju3.chishi=b.日支
  LEFT JOIN juniun ju4 ON ju4.nikkan=b.日干 AND ju4.chishi=j.時支
),

-- 天干通変星（四柱の天干）
tstar_map AS (
  SELECT b.birth_dt,
         ty.star AS 年干通変星,
         tm.star AS 月干通変星,
         td.star AS 日干通変星,
         tt.star AS 時干通変星
  FROM base b
  LEFT JOIN timepillar tp ON tp.birth_dt=b.birth_dt
  LEFT JOIN tsuhensei ty ON ty.nikkan=b.日干 AND ty.target=b.年干
  LEFT JOIN tsuhensei tm ON tm.nikkan=b.日干 AND tm.target=b.月干
  LEFT JOIN tsuhensei td ON td.nikkan=b.日干 AND td.target=b.日干
  LEFT JOIN tsuhensei tt ON tt.nikkan=b.日干 AND tt.target=tp.時干
),

-- 天同地沖 / 天地徳合マップ
chichuu_map AS ( SELECT tisi, gou FROM tendouchichuu ),
tok_map     AS ( SELECT tenkan, MIN(toku) AS toku FROM tenchidokugo GROUP BY tenkan ),
dokugo_gou  AS ( SELECT tisi, gou FROM tenchidokugo ),

-- 立運計算
diffs AS (
  SELECT b.*,
         (SELECT label FROM prev_sekki) AS 直前節気,
         (SELECT label FROM next_sekki) AS 直後節気,
         CASE WHEN b.dir='順運'
              THEN TIMESTAMPDIFF(DAY, b.birth_dt, (SELECT n.s_dt FROM next_sekki n))
              ELSE TIMESTAMPDIFF(DAY, (SELECT v.s_dt FROM prev_sekki v), b.birth_dt)
         END AS diff_days
  FROM base b
),
calc AS (
  SELECT
    diff_days,
    FLOOR(diff_days/3) AS 立運年数,
    ROUND((diff_days - (FLOOR(diff_days/3)*3))*4,0) AS 立運月数,
    birth_dt, gender, 年干, 月干, 日干, dir,
    年柱通番, 月柱通番, 日柱通番,
    年柱干支, 月柱干支, 日柱干支,
    直前節気, 直後節気
  FROM diffs
),
liyun AS (
  SELECT
    c.*,
    YEAR(c.birth_dt) + c.立運年数 + FLOOR((MONTH(c.birth_dt)-1 + c.立運月数)/12) AS 運年,
    MOD((MONTH(c.birth_dt)-1 + c.立運月数),12) + 1 AS 運月
  FROM calc c
)

-- ================= 最終 SELECT（縦型：項目, 時柱, 日柱, 月柱, 年柱） =================
SELECT '干支番号' AS 項目,
       '' AS 時柱,
      liyun.日柱通番 + 1 AS 日柱,
      liyun.月柱通番 + 1 AS 月柱,
      liyun.年柱通番 + 1 AS 年柱
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '通変星',
       ts.時干通変星,
       '',
       ts.月干通変星,
       ts.年干通変星
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '干支',
       tp.時柱干支,
       liyun.日柱干支,
       liyun.月柱干支,
       liyun.年柱干支
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '天干',
       tp.時干,
       b.日干,
       b.月干,
       b.年干
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '地支',
       j.時支,
       b.日支,
       b.月支,
       b.年支
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '冲・合・刑',
       '----','----','----','-----'
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '蔵干の五行',
       CONCAT_WS(',',zs.時五1,zs.時五2,zs.時五3),
       CONCAT_WS(',',zs.日五1,zs.日五2,zs.日五3),
       CONCAT_WS(',',zs.月五1,zs.月五2,zs.月五3),
       CONCAT_WS(',',zs.年五1,zs.年五2,zs.年五3)
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '蔵干',
       zs.時蔵干,
       zs.日蔵干,
       zs.月蔵干,
       zs.年蔵干
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '蔵干通変星',
       CONCAT_WS(',',zs.時星1,zs.時星2,zs.時星3),
       CONCAT_WS(',',zs.日星1,zs.日星2,zs.日星3),
       CONCAT_WS(',',zs.月星1,zs.月星2,zs.月星3),
       CONCAT_WS(',',zs.年星1,zs.年星2,zs.年星3)
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '十二運',
       ju.時十二運,
       ju.日十二運,
       ju.月十二運,
       ju.年十二運
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '空亡',
       '----',
       ku.日空亡,
       '----',
       '-----'
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '伏吟',
       tp.時柱干支,
       liyun.日柱干支,
       liyun.月柱干支,
       liyun.年柱干支
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '天同地沖',
       CONCAT(tp.時干,(SELECT c.gou FROM chichuu_map c WHERE c.tisi=j.時支)),
       CONCAT(b.日干,(SELECT c.gou FROM chichuu_map c WHERE c.tisi=b.日支)),
       CONCAT(b.月干,(SELECT c.gou FROM chichuu_map c WHERE c.tisi=b.月支)),
       CONCAT(b.年干,(SELECT c.gou FROM chichuu_map c WHERE c.tisi=b.年支))
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '天地徳合',
       CONCAT((SELECT t.toku FROM tok_map t WHERE t.tenkan=tp.時干),
              (SELECT g.gou FROM dokugo_gou g WHERE g.tisi=j.時支)),
       CONCAT((SELECT t.toku FROM tok_map t WHERE t.tenkan=b.日干),
              (SELECT g.gou FROM dokugo_gou g WHERE g.tisi=b.日支)),
       CONCAT((SELECT t.toku FROM tok_map t WHERE t.tenkan=b.月干),
              (SELECT g.gou FROM dokugo_gou g WHERE g.tisi=b.月支)),
       CONCAT((SELECT t.toku FROM tok_map t WHERE t.tenkan=b.年干),
              (SELECT g.gou FROM dokugo_gou g WHERE g.tisi=b.年支))
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '天剋地沖',
       CAST((SELECT t.tichu FROM tengokuchichu t WHERE t.tenkan=tp.時干 LIMIT 1) AS CHAR),
       CAST((SELECT t.tichu FROM tengokuchichu t WHERE t.tenkan=b.日干 LIMIT 1) AS CHAR),
       CAST((SELECT t.tichu FROM tengokuchichu t WHERE t.tenkan=b.月干 LIMIT 1) AS CHAR),
       CAST((SELECT t.tichu FROM tengokuchichu t WHERE t.tenkan=b.年干 LIMIT 1) AS CHAR)
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '宿命大半会',
       (SELECT syukumei FROM syukumeidaihankai WHERE tisi=j.時支 LIMIT 1),
       (SELECT syukumei FROM syukumeidaihankai WHERE tisi=b.日支 LIMIT 1),
       (SELECT syukumei FROM syukumeidaihankai WHERE tisi=b.月支 LIMIT 1),
       (SELECT syukumei FROM syukumeidaihankai WHERE tisi=b.年支 LIMIT 1)
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
UNION ALL
SELECT '調候用神',
       '',
       (SELECT yj.youjin FROM choko_youjin yj WHERE yj.nikkan=b.日干 AND yj.gessi=b.月支 LIMIT 1),
       '',
       ''
FROM liyun
JOIN base b             ON b.birth_dt = liyun.birth_dt
LEFT JOIN timepillar tp ON tp.birth_dt= liyun.birth_dt
LEFT JOIN jishi j       ON j.birth_dt = liyun.birth_dt
LEFT JOIN zstar zs      ON zs.birth_dt= liyun.birth_dt
LEFT JOIN kuubou_map ku ON ku.birth_dt= liyun.birth_dt
LEFT JOIN juniun_map ju ON ju.birth_dt= liyun.birth_dt
LEFT JOIN tstar_map ts  ON ts.birth_dt = liyun.birth_dt
;

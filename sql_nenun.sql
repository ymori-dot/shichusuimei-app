WITH RECURSIVE
params AS (
  SELECT STR_TO_DATE(%s,'%%Y-%%m-%%d %%H:%%i') AS birth_dt,
         %s  AS gender,
         %s  AS y_from,
         %s  AS y_to
),

-- 日干を取得（基準：日柱通番）
daypillar AS (
  SELECT MOD(TIMESTAMPDIFF(DAY,'1916-03-28',p.birth_dt),60) AS 日柱通番,
         p.y_from, p.y_to
  FROM params p
),
base_day AS (
  SELECT e.tenkan AS 日干, d.y_from, d.y_to
  FROM daypillar d
  LEFT JOIN eto60 e ON e.id = d.日柱通番
),

-- y_from..y_to を生成
y_seq AS (
  SELECT bd.y_from AS y, bd.y_to
  FROM base_day bd
  UNION ALL
  SELECT y+1, y_to FROM y_seq WHERE y < y_to
)

SELECT
  y AS 西暦,
  e.eto   AS 年干支,
  t.star     AS 年干通変星,                        -- 日干 × 年干
  j.unsei    AS 十二運                            -- 日干 × 年支
FROM y_seq
CROSS JOIN base_day bd
LEFT JOIN eto60     e ON e.id = MOD(((y - 1924)+60),60)
LEFT JOIN tsuhensei t ON t.nikkan = bd.日干 AND t.target = e.tenkan
LEFT JOIN juniun    j ON j.nikkan = bd.日干 AND j.chishi = e.chishi
ORDER BY y;

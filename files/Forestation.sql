SELECT * FROM forest_area
WHERE forest_area_sqkm IS NULL;
SELECT * FROM land_area
WHERE total_area_sqkm IS NULL;
SELECT * FROM regions;

ALTER TABLE land_area
ADD total_area_sqkm FLOAT;
UPDATE land_area 
SET total_area_sqkm = total_area_sq_mi*2.59;

/* 1. Global Situation */
-- Total forest area of the world in 1990
SELECT forest_area_sqkm AS total_forest_1990 FROM forest_area
WHERE year = 1990 AND country_code = 'WLD';

-- Total forest area of the world in 2016
SELECT forest_area_sqkm AS total_forest_2016 FROM forest_area
WHERE year = 2016 AND country_code = 'WLD';

-- Total loss and % 1990-2016
WITH Forest_1990 AS
(
	SELECT forest_area_sqkm AS total_1990 FROM forest_area
	WHERE year = 1990 AND country_code = 'WLD'
), Forest_2016 AS
(
	SELECT forest_area_sqkm AS total_2016 FROM forest_area
	WHERE year = 2016 AND country_code = 'WLD'
)
SELECT f90.total_1990 - f16.total_2016 AS total_loss,
	ROUND((f90.total_1990 - f16.total_2016)/f90.total_1990*100, 2) AS percent_loss
FROM Forest_1990 f90, Forest_2016 f16;

-- Compare to land area of .... in 2016
WITH Forest_1990 AS
(
	SELECT forest_area_sqkm AS total_1990 FROM forest_area
	WHERE year = 1990 AND country_code = 'WLD'
), Forest_2016 AS
(
	SELECT forest_area_sqkm AS total_2016 FROM forest_area
	WHERE year = 2016 AND country_code = 'WLD'
)
SELECT TOP 1 * FROM land_area 
WHERE year = 2016 
	AND total_area_sqkm < (SELECT f90.total_1990 - f16.total_2016 AS total_loss
							FROM Forest_1990 f90, Forest_2016 f16)
ORDER BY total_area_sqkm DESC;

/* 2. Regional Outlook */
-- % world's forest area in 2016
WITH Forest_2016 AS
(
	SELECT forest_area_sqkm AS total_forest FROM forest_area
	WHERE year = 2016 AND country_code = 'WLD'
), Land_2016 AS
(
	SELECT la.total_area_sqkm AS total_land FROM land_area la
	WHERE year = 2016 AND country_code = 'WLD'
)
SELECT ROUND(f16.total_forest/l16.total_land*100, 2) AS forest_percentage
FROM Forest_2016 f16, Land_2016 l16;

-- % world's forest area in 1990
WITH Forest_1990 AS
(
	SELECT forest_area_sqkm AS total_forest FROM forest_area
	WHERE year = 1990 AND country_code = 'WLD'
), Land_1990 AS
(
	SELECT la.total_area_sqkm AS total_land FROM land_area la
	WHERE year = 1990 AND country_code = 'WLD'
)
SELECT ROUND(f90.total_forest/l90.total_land*100, 2) AS forest_percentage
FROM Forest_1990 f90, Land_1990 l90;

-- Regions with highest and lowest forest % in 1990 and 2016
WITH Forest_by_region AS 
(
    SELECT r.region,
        SUM(CASE WHEN fa.year = 1990 THEN fa.forest_area_sqkm END) AS forest_1990,
        SUM(CASE WHEN fa.year = 2016 THEN fa.forest_area_sqkm END) AS forest_2016
    FROM forest_area fa
    JOIN regions r ON r.country_code = fa.country_code
    WHERE fa.year IN (1990, 2016) AND r.region != 'World'
    GROUP BY r.region
), Land_by_region AS 
(
    SELECT r.region,
        SUM(CASE WHEN la.year = 1990 THEN la.total_area_sqkm END) AS land_1990,
        SUM(CASE WHEN la.year = 2016 THEN la.total_area_sqkm END) AS land_2016
    FROM land_area la
    JOIN regions r ON r.country_code = la.country_code
    WHERE la.year IN (1990, 2016) AND r.region != 'World'
    GROUP BY r.region
)
SELECT f.region,
    ROUND(f.forest_1990 / l.land_1990 * 100, 2) AS forest_percent_1990,
    ROUND(f.forest_2016 / l.land_2016 * 100, 2) AS forest_percent_2016
FROM Forest_by_region f
JOIN Land_by_region l ON l.region = f.region
ORDER BY forest_percent_1990 DESC;

/* 3. Country-level Detail */
/* Success Stories */
-- Rank the forest area differences by country between 1990-2016 (INCREASE)
WITH Forest_1990 AS
(
	SELECT country_name, forest_area_sqkm AS forest_90 FROM forest_area
	WHERE year = 1990
), Forest_2016 AS
(
	SELECT country_name, forest_area_sqkm AS forest_16 FROM forest_area
	WHERE year = 2016
), Forest_dif AS
(
	SELECT f16.country_name, f16.forest_16 - f90.forest_90 AS forest_dif 
	FROM Forest_2016 f16, Forest_1990 f90
	WHERE f90.country_name = f16.country_name
)
SELECT fd.country_name, 
	fd.forest_dif,
	RANK() OVER (ORDER BY fd.forest_dif DESC) AS 'forest_rank'
FROM Forest_dif fd
WHERE fd.country_name != 'World';

-- Rank the forest area differences in PERCENTAGE by country between 1990-2016
WITH Forest_changes AS 
(
    SELECT fa.country_name,
        SUM(CASE WHEN year = 1990 THEN forest_area_sqkm END) AS forest_90,
        SUM(CASE WHEN year = 2016 THEN forest_area_sqkm END) AS forest_16
    FROM forest_area fa
    WHERE year IN (1990, 2016) AND country_name != 'World'
    GROUP BY fa.country_name
)
SELECT f.country_name,
    f.forest_90,
    f.forest_16,
    ROUND(f.forest_16 - f.forest_90, 2) AS forest_dif,
    ROUND((f.forest_16 - f.forest_90) / f.forest_90 * 100, 2) AS forest_dif_percent,
    RANK() OVER (ORDER BY (f.forest_16 - f.forest_90) / f.forest_90 * 100 DESC) AS forest_percent_rank
FROM Forest_changes f
WHERE forest_90 IS NOT NULL AND forest_16 IS NOT NULL;

/* Largest Concerns */
-- Rank the forest area differences by country between 1990-2016 (DECREASE)
WITH Forest_changes AS 
(
    SELECT fa.country_name,
        SUM(CASE WHEN year = 1990 THEN forest_area_sqkm END) AS forest_90,
        SUM(CASE WHEN year = 2016 THEN forest_area_sqkm END) AS forest_16
    FROM forest_area fa
    WHERE year IN (1990, 2016) AND country_name != 'World'
    GROUP BY fa.country_name
)
SELECT f.country_name,
	r.region,
    ROUND(f.forest_16 - f.forest_90, 2) AS forest_dif,
    RANK() OVER (ORDER BY (f.forest_16 - f.forest_90) ASC) AS forest_rank
FROM Forest_changes f
JOIN regions r ON r.country_name = f.country_name
WHERE forest_90 IS NOT NULL AND forest_16 IS NOT NULL;

-- Rank the forest area differences in PERCENTAGE by country between 1990-2016 (DECREASE)
WITH Forest_changes AS 
(
    SELECT fa.country_name,
        r.region,
        SUM(CASE WHEN fa.year = 1990 THEN fa.forest_area_sqkm END) AS forest_90,
        SUM(CASE WHEN fa.year = 2016 THEN fa.forest_area_sqkm END) AS forest_16
    FROM forest_area fa
    JOIN regions r ON r.country_name = fa.country_name
    WHERE fa.year IN (1990, 2016)
      AND fa.country_name != 'World'
    GROUP BY fa.country_name, r.region
)
SELECT country_name,
    region,
    forest_90,
    forest_16,
    ROUND(forest_16 - forest_90, 2) AS forest_dif,
    ROUND((forest_16 - forest_90) / forest_90 * 100, 2) AS forest_dif_percent,
    RANK() OVER (ORDER BY (forest_16 - forest_90) / forest_90 ASC) AS forest_percent_rank
FROM Forest_changes
WHERE forest_90 IS NOT NULL AND forest_16 IS NOT NULL;

/* Quartiles */
-- Count of Countries Grouped by Forestation Percentage Quartiles in 2016 (CASE WHEN)
WITH Forestation_2016 AS
(
	SELECT fa.country_name, ROUND(fa.forest_area_sqkm/la.total_area_sqkm*100, 2) AS forestation
	FROM forest_area fa
	JOIN land_area la ON la.country_name = fa.country_name AND la.year = fa.year
	WHERE fa.year = 2016 
		AND forest_area_sqkm IS NOT NULL
		AND total_area_sqkm IS NOT NULL
), Country_quartile AS
(
	SELECT f16.country_name,
		CASE
			WHEN f16.forestation <= 25 THEN 'Quartile 1'
			WHEN f16.forestation <= 50 THEN 'Quartile 2'
			WHEN f16.forestation <= 75 THEN 'Quartile 3'
			ELSE 'Quartile 4'
		END AS forestation_quartile
	FROM Forestation_2016 f16
)
SELECT cq.forestation_quartile AS quartile, COUNT(cq.country_name) AS country_count
FROM Country_quartile cq
GROUP BY cq.forestation_quartile
ORDER BY cq.forestation_quartile;

-- OPTIMISED
WITH Forestation_2016 AS (
    SELECT
        fa.country_name,
        ROUND(fa.forest_area_sqkm / la.total_area_sqkm * 100, 2) AS forestation
    FROM forest_area fa
    JOIN land_area la
        ON la.country_name = fa.country_name
        AND la.year = fa.year
    WHERE fa.year = 2016
      AND fa.forest_area_sqkm IS NOT NULL
      AND la.total_area_sqkm IS NOT NULL
)
SELECT
    CASE
        WHEN forestation <= 25 THEN 'Quartile 1'
        WHEN forestation <= 50 THEN 'Quartile 2'
        WHEN forestation <= 75 THEN 'Quartile 3'
        ELSE 'Quartile 4'
    END AS quartile,
    COUNT(country_name) AS country_count
FROM Forestation_2016
GROUP BY
    CASE
        WHEN forestation <= 25 THEN 'Quartile 1'
        WHEN forestation <= 50 THEN 'Quartile 2'
        WHEN forestation <= 75 THEN 'Quartile 3'
        ELSE 'Quartile 4'
    END
ORDER BY quartile;

-- Top Countries of the 4th Quartile in 2016
WITH Forestation_2016 AS
(
	SELECT fa.country_name, ROUND(fa.forest_area_sqkm/la.total_area_sqkm*100, 2) AS forestation
	FROM forest_area fa
	JOIN land_area la ON la.country_name = fa.country_name AND la.year = fa.year
	WHERE fa.year = 2016 
		AND forest_area_sqkm IS NOT NULL
		AND total_area_sqkm IS NOT NULL
), Country_quartile AS
(
	SELECT f16.country_name,
		CASE
			WHEN f16.forestation <= 25 THEN 'Quartile 1'
			WHEN f16.forestation <= 50 THEN 'Quartile 2'
			WHEN f16.forestation <= 75 THEN 'Quartile 3'
			ELSE 'Quartile 4'
		END AS forestation_quartile
	FROM Forestation_2016 f16
)
SELECT cq.country_name, r.region, f16.forestation
FROM Country_quartile cq
JOIN Forestation_2016 f16 ON f16.country_name = cq.country_name
JOIN regions r ON r.country_name = cq.country_name
WHERE cq.forestation_quartile = 'Quartile 4'
GROUP BY cq.country_name, r.region, f16.forestation
ORDER BY f16.forestation DESC;

-- OPTIMISED
WITH Forestation_2016 AS (
    SELECT
        fa.country_name,
        r.region,
        ROUND(fa.forest_area_sqkm / la.total_area_sqkm * 100, 2) AS forestation
    FROM forest_area fa
    JOIN land_area la ON la.country_name = fa.country_name AND la.year = fa.year
    JOIN regions r ON r.country_name = fa.country_name
    WHERE fa.year = 2016
      AND fa.forest_area_sqkm IS NOT NULL
      AND la.total_area_sqkm IS NOT NULL
)
SELECT
    country_name,
    region,
    forestation
FROM Forestation_2016
WHERE forestation > 75  -- Quartile 4 equivalent
ORDER BY forestation DESC;

/* 4. Extra Query */
-- Number of Countries with the largest forest area by year and forestation level (Low, Medium, High)
WITH Forestation AS 
(
    SELECT
        fa.year,
        CASE
            WHEN fa.forest_area_sqkm / la.total_area_sqkm * 100 <  20 THEN 'Low'
            WHEN fa.forest_area_sqkm / la.total_area_sqkm * 100 <= 50 THEN 'Medium'
            ELSE 'High'
        END AS forestation_level
    FROM forest_area fa
    JOIN land_area la ON la.country_name = fa.country_name AND la.year = fa.year
    WHERE fa.year IN (1990, 2016)
      AND fa.country_name != 'World'
      AND fa.forest_area_sqkm IS NOT NULL
      AND la.total_area_sqkm IS NOT NULL
)
SELECT forestation_level,
    COUNT(CASE WHEN year = 1990 THEN 1 END) AS country_count_1990,
    COUNT(CASE WHEN year = 2016 THEN 1 END) AS country_count_2016
FROM Forestation
GROUP BY forestation_level
ORDER BY forestation_level;

-- Top countries with the largest forest area by each income group and region in 2016
WITH Country_rank AS
(
	SELECT fa.country_name, r.region, r.income_group, fa.forest_area_sqkm,
		RANK() OVER(PARTITION BY r.region, r.income_group ORDER BY fa.forest_area_sqkm DESC) AS country_rank
	FROM forest_area fa
	JOIN regions r ON r.country_name = fa.country_name
	WHERE fa.country_name != 'World' 
		AND fa.year = 2016
		AND fa.forest_area_sqkm IS NOT NULL
)
SELECT cr.country_name, cr.region, cr.income_group, cr.forest_area_sqkm
FROM Country_rank cr
WHERE cr.country_rank = 1
ORDER BY cr.region, cr.income_group;

-- Top countries with the largest forest area by each income group and region in 1990
WITH Country_rank AS
(
	SELECT fa.country_name, r.region, r.income_group, fa.forest_area_sqkm,
		RANK() OVER(PARTITION BY r.region, r.income_group ORDER BY fa.forest_area_sqkm DESC) AS country_rank
	FROM forest_area fa
	JOIN regions r ON r.country_name = fa.country_name
	WHERE fa.country_name != 'World' 
		AND fa.year = 1990
		AND fa.forest_area_sqkm IS NOT NULL
)
SELECT cr.country_name, cr.region, cr.income_group, cr.forest_area_sqkm
FROM Country_rank cr
WHERE cr.country_rank = 1
ORDER BY cr.region, cr.income_group;
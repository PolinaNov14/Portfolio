/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Новикова Полина
 * Дата:18.01.2025-19.01.2025
*/
-- Задача 1. Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
category as (
    SELECT *,
    case 
        when city = 'Санкт-Петербург'
        then 'Санкт-Петербург'
        else 'ЛенОбл'
    end AS region,
    case 
        when days_exposition between 1 and 30 then 'до месяца'
        when days_exposition between 31 and 90 then 'до трех месяцев'
        when days_exposition between 91 and 180 then 'полгода'
        when days_exposition > 180 then 'после полугода'
        else 'прочие' -- Отдельная категория
    end as activity_time,
    last_price/total_area as metr_price
    FROM real_estate.advertisement as a 
    join real_estate.flats as f on a.id=f.id
    join real_estate.city as c on c.city_id=f.city_id
    where f.id in (select id from filtered_id)
    AND type_id = 'F8EM' 
    AND a.days_exposition IS NOT NULL) -- Не будет категории "прочие"
    SELECT region AS "Регион",
           activity_time AS "Сегмент активности",
           count (*) AS "Кол-во объявлений",
           round(avg(metr_price)::numeric,2) as "Ср. ст-ть кв.м",
           round(avg(total_area)::numeric,2) as "Ср. площадь",
           percentile_disc (0.5) WITHIN GROUP (ORDER BY rooms) as "Медиана кол-ва комнат",
           percentile_disc (0.5) WITHIN GROUP (ORDER BY balcony) as "Медиана кол-ва балконов",
           percentile_disc (0.5) WITHIN GROUP (ORDER BY floor) as  "Медиана этажности"
    FROM category
    GROUP BY region, activity_time
    ORDER BY region desc, activity_time;

--Задача 2. Сезонность объявлений
WITH limits AS
    (SELECT  
          PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
          PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
          PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
          PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
          PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
 ),
filtered_id AS
    (SELECT id
    FROM real_estate.flats  
    WHERE total_area < (SELECT total_area_limit FROM limits)
          AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
          AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
          AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
          AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
 ),
 -- Найдем стоимость кв метра:
 price AS ( SELECT a.id,
          f.total_area,
          (a.last_price/f.total_area) AS price_kvm,
          EXTRACT ('month' FROM a.first_day_exposition::DATE) AS "Номер месяца",
          EXTRACT ('month' FROM a.first_day_exposition::DATE + a.days_exposition::INTEGER) AS "Месяц снятия"  
          FROM real_estate.flats AS f
          JOIN real_estate.advertisement AS a ON a.id=f.id
          WHERE f.id IN (SELECT id FROM filtered_id) AND type_id = 'F8EM'
          AND a.days_exposition IS NOT NULL), -- В замечаниях было указать в arch_month, но мне кажется правильнее здесь указать
-- Статистика опубликованных по месяцу публикации:
publ_month AS (SELECT "Номер месяца", 
     COUNT(id) AS "Кол-во объявлений",
     ROUND(AVG(price_kvm)::numeric, 2) AS "Ср. цена за кв.м", 
     ROUND(AVG(total_area)::numeric, 2) AS "Ср. площадь"  
FROM price
GROUP BY "Номер месяца"
ORDER BY "Номер месяца"
),
-- Статистика снятых с продажи по месяцу публикации:
arch_month AS          
     (SELECT "Месяц снятия" , 
      COUNT (id) AS "Кол-во объявлений",
      ROUND (AVG(price_kvm)::numeric, 2) AS "Ср. цена за кв.м", 
      ROUND (AVG(total_area)::numeric, 2) AS "Ср. площадь"
FROM price
GROUP BY "Месяц снятия" 
ORDER BY "Месяц снятия" 
)
  SELECT 'опубликовано' AS "Статус", 
        *,
        RANK() OVER (ORDER BY "Кол-во объявлений" DESC) AS "Ранг"
        FROM publ_month
UNION ALL
SELECT 'снято' AS "Статус", 
        *,
        RANK() OVER (ORDER BY "Кол-во объявлений" DESC) AS "Ранг"
        FROM arch_month;

-- Задача 3. Анализ рынка недвижимости Ленобласти
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Найдем количество снятых с продажи объявлений:
sold AS (SELECT c.city,
                count(a.id) AS sold_id,
                round(avg(a.last_price/f.total_area)::numeric,2) AS avg_sold_m2,
                round(avg(f.total_area):: NUMERIC,2) AS avg_total_area,
                avg(a.days_exposition)::numeric(7,3) AS avg_days
        FROM real_estate.advertisement as a 
        JOIN real_estate.flats as f on a.id=f.id
        JOIN real_estate.city as c on c.city_id=f.city_id
        WHERE a.days_exposition IS NOT NULL
              AND f.id IN (SELECT * FROM filtered_id)
        GROUP BY c.city
),
-- Найдем общее количество объявлений:
all_id AS (SELECT c.city,
                  count(a.id) AS total_id
          FROM real_estate.advertisement as a 
          JOIN real_estate.flats as f on a.id=f.id
          JOIN real_estate.city as c on c.city_id=f.city_id
          WHERE f.id IN (SELECT * FROM filtered_id)
          GROUP BY c.city
)
SELECT s.city AS "Населенный пункт",
       al.total_id AS "Общее кол-во объвлений",
       s.sold_id AS "Кол-во снятых объявлений",
       round(s.sold_id/al.total_id::NUMERIC,4) AS "Доля снятых к общему",
       s.avg_sold_m2 AS "Ср. ст-ть кв м",
       s.avg_total_area AS "Ср. площадь",
       s.avg_days AS "Ср. кол-во дней"
FROM sold AS s 
JOIN all_id AS al ON al.city=s.city
WHERE s.city <> 'Санкт-Петербург'
      AND al.total_id > 50
ORDER BY "Кол-во снятых объявлений" DESC 
LIMIT 15; 

/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Новикова Полина
 * Дата: 28.12.2024
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
-- Напишите ваш запрос здесь
WITH t1 AS (SELECT count(payer) AS all_users,
	sum(payer) AS paying_users
FROM fantasy.users)
SELECT *, ROUND((paying_users::numeric/all_users),3) AS part
FROM t1; 
-- 1.2. Доля платящих пользователей в разрезе расы персо нажа:
-- Напишите ваш запрос здесь
WITH t2 AS  (SELECT race, 
	         count(payer) AS all_users, 
	         sum(payer) AS paying_users
	         FROM fantasy.users AS u
	         LEFT JOIN fantasy.race AS r ON u.race_id = r.race_id 
	         GROUP BY race)
SELECT *,
	ROUND((paying_users::numeric/all_users),3) AS part
FROM t2;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
-- Напишите ваш запрос здесь
SELECT COUNT(amount),
	sum(amount),
	min(amount),
	max(amount), 
	avg(amount)::NUMERIC(10, 2),
	PERCENTILE_DISC(0.50) --медиана
 WITHIN GROUP (ORDER BY amount) AS mediana,
    STDDEV(amount)::NUMERIC(10, 2) AS stand_amount --стандартное отклонение
FROM fantasy.events
WHERE amount>0; 
-- 2.2: Аномальные нулевые покупки:
-- Напишите ваш запрос здесь
SELECT count(amount) AS amount_null,
(count(amount)::numeric/(SELECT count(transaction_id)FROM fantasy.events)) AS part_to_all
FROM fantasy.events 
WHERE amount=0;
-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
-- Напишите ваш запрос здесь
WITH t3 AS (
    SELECT
        u.payer AS payer,
        e.id AS user_id,
        COUNT(e.transaction_id) AS total_orders,
        SUM(e.amount) AS total_amount
     FROM fantasy.events AS e
     LEFT JOIN fantasy.users AS u ON e.id = u.id 
     WHERE e.amount > 0
     GROUP BY u.payer, e.id)
SELECT CASE 
	WHEN payer = 0
	THEN 'неплатящий игрок'
	WHEN payer = 1
	THEN 'платящий игрок'
	ELSE 'другое'
    END AS payer,
    COUNT(user_id),
    avg(total_orders)::NUMERIC(4, 2) AS avg_total_orders,
    avg(total_amount)::NUMERIC(7, 2) AS avg_total_amount
FROM t3
GROUP BY payer;
-- 2.4: Популярные эпические предметы:
-- Напишите ваш запрос здесь
 WITH t4 AS (
  SELECT
  COUNT(DISTINCT transaction_id) AS total_orders,
  COUNT(DISTINCT id) AS total_players
  FROM fantasy.events
  WHERE amount > 0
)
SELECT
 i.game_items AS game_item,
 COUNT(DISTINCT e.transaction_id) AS total_orders,
 COUNT(DISTINCT e.id) AS total_players,
 (COUNT(e.transaction_id)::real / (SELECT total_orders FROM t4)*100)::NUMERIC(6,4) AS otn,
 (COUNT(DISTINCT e.id)::real / (SELECT total_players FROM t4)*100)::NUMERIC(6,4) AS part_player
FROM fantasy.events AS e
LEFT JOIN fantasy.items AS i ON e.item_code = i.item_code
WHERE amount > 0
GROUP BY game_item
ORDER BY total_players DESC;
-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
-- Напишите ваш запрос здесь
WITH t5 AS (
 SELECT DISTINCT r.race AS race,
 COUNT(u.id) OVER(PARTITION BY r.race) AS total_players,
 SUM(u.payer) OVER(PARTITION BY r.race) AS total_payers
 FROM fantasy.users AS u
 LEFT JOIN fantasy.race AS r on  r.race_id=u.race_id
),
t6 AS ( 
   SELECT DISTINCT e.id,
        r.race AS race,
        u.payer,
        count(e.id) as count_id,
        count(transaction_id) AS total_orders,
        sum (amount) AS sum_all
    FROM fantasy.events AS e
    LEFT JOIN fantasy.users AS u ON u.id = e.id
    LEFT JOIN fantasy.race AS r ON u.race_id = r.race_id
    WHERE e.amount > 0
    GROUP BY race,e.id,u.payer),
t7 AS ( 
	SELECT race , 
		COUNT(payer) AS total_players_1,
		SUM(payer) AS total_payers_2
    FROM t6
    group by race),
t8 AS (
 SELECT
 DISTINCT e.id,r.race,
 COUNT(e.transaction_id) OVER(PARTITION BY e.id, r.race) AS total_purchases,
 SUM(e.amount) OVER(PARTITION BY e.id, r.race) AS total_amount,
 AVG(e.amount) OVER(PARTITION BY e.id, r.race) AS avg_amount
 FROM fantasy.events AS e
 JOIN fantasy.users AS u on e.id=u.id
 JOIN fantasy.race AS r on r.race_id=u.race_id
 WHERE amount>0), 
t9 AS(
    SELECT
        race, 
        COUNT(id), 
        AVG(total_purchases)::numeric(8,2) AS avg_purc_per_player, 
        AVG(total_amount)::numeric(8,2) AS avg_total_amount_per_player, 
        AVG(total_amount)/AVG(total_purchases) AS avg_amount_per_player
    FROM t8
    GROUP BY race)
SELECT
    t5.race AS race, 
    t5.total_players, --общее количество зарегистрированных игроков
    t7.total_players_1, --количество игроков, которые совершают внутриигровые покупки, и их доля от общего количества
    (t7.total_players_1::real / t5.total_players)::numeric(4,3) AS players_w_purch_share, --доля игроков, которые совершают внутриигровые покупки
    (t7.total_payers_2::real / t7.total_players_1)::numeric(4,3) AS payers_w_purch, --доля платящих игроков от количества игроков, которые совершили покупки
    t9.avg_purc_per_player, -- среднее количество покупок на одного игрока
    t9.avg_total_amount_per_player,--средняя стоимость одной покупки на одного игрока
     t9.avg_amount_per_player::numeric(6,2) --средняя суммарная стоимость всех покупок на одного игрока
FROM t9 
    LEFT JOIN t5 ON t9.race = t5.race
    LEFT JOIN t7 ON t9.race = t7.race
ORDER BY t9.race;

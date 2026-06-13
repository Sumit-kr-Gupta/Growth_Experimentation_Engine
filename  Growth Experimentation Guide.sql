CREATE DATABASE growth_experimentation;
USE growth_experimentation;
SELECT COUNT(*)  AS total_users FROM experiment_data;

/*EXPERIMENT SPLIT*/
SELECT con_treat,
COUNT(*) AS users
FROM experiment_data
GROUP BY con_treat;

/*OVERALL CONVERSION RATE*/
SELECT COUNT(*) AS USERS,
SUM(converted) AS CONVERSIONS,
ROUND(AVG(converted)*100,2) AS CONVERSION_RATE
FROM experiment_data;

/*EXPERIMENT PERFORMANCE*/
SELECT con_treat,
COUNT(*) AS USERS,
SUM(converted) AS CONVERSIONS,
ROUND(AVG(converted)*100,2) AS CONVERSION_RATE
FROM experiment_data
GROUP BY con_treat;

/*ABSOLUTE LIFT*/
SELECT ROUND((AVG(CASE WHEN con_treat = 'treatment' THEN converted END) 
- 
AVG(CASE WHEN con_treat = 'control' THEN converted END)) * 100,2)
AS ABSOLUTE_LIFT FROM experiment_data;

/*RELATIVE LIFT*/
SELECT ROUND
(((AVG(CASE WHEN con_treat = 'treatment' THEN converted END)
- 
AVG(CASE WHEN con_treat = 'control' THEN converted
END)) / AVG(CASE
WHEN con_treat = 'control' THEN converted
END)) * 100,2)
AS RELATIVE_LIFT
FROM experiment_data;

/*EXPERIMENT WINNER*/
SELECT CASE
WHEN AVG(CASE WHEN con_treat='treatment'
THEN converted END)
>
AVG(CASE WHEN con_treat='control'
THEN converted END)
THEN 'Treatment Wins'
ELSE 'Control Wins'
END AS WINNER
FROM experiment_data;

/*COUNTRY PERFORMANCE*/
SELECT country,
COUNT(*) AS USERS,
SUM(converted) AS CONVERSIONS,
ROUND(AVG(converted)*100,2) AS CONVERSION_RATE
FROM experiment_data
GROUP BY country
ORDER BY CONVERSION_RATE DESC;

/*COUNTRY + EXPERIMENT ANALYSIS*/
SELECT country,con_treat,
COUNT(*) AS USERS,
ROUND(AVG(converted)*100,2) AS CONVERSION_RATE
FROM experiment_data
GROUP BY country, con_treat
ORDER BY country;

/*COUNTRY RANKING (WINDOW FUNCTION)*/
SELECT country,
ROUND(AVG(converted)*100,2) AS CONVERSION_RATE,
RANK() OVER(
ORDER BY AVG(converted) DESC) AS COUNTRY_RANK
FROM experiment_data
GROUP BY country;

/*EXECUTIVE SUMMARY VIEW*/
CREATE VIEW executive_summary AS
SELECT COUNT(*) AS TOTAL_USERS,
SUM(converted) AS TOTAL_CONVERSIONS,
ROUND(AVG(converted)*100,2) AS OVERALL_CVR,
ROUND(AVG(CASE WHEN con_treat='control'
THEN converted END)*100,2) AS CONTROL_CVR,
ROUND(AVG(CASE WHEN con_treat='treatment'
THEN converted END)*100,2) AS TREATMENT_CVR
FROM experiment_data;

/*EXECUTIVE DASHBOARD QUERY*/
SELECT * FROM executive_summary;

/*TRAFFIC RANKING*/
SELECT country,COUNT(*) AS users,
DENSE_RANK() OVER(ORDER BY COUNT(*) DESC) AS traffic_rank
FROM experiment_data GROUP BY country;

/*EXPERIMENT KPI VIEW*/
CREATE VIEW experiment_kpi AS
SELECT con_treat,COUNT(*) AS users,
SUM(converted) AS conversions,
ROUND(AVG(converted)*100,2) AS conversion_rate
FROM experiment_data GROUP BY con_treat;

SELECT * FROM experiment_kpi;

/*COUNTRY KPI VIEW*/
CREATE VIEW country_kpi AS
SELECT country,
COUNT(*) AS users,SUM(converted) AS conversions,
ROUND(AVG(converted)*100,2) AS conversion_rate
FROM experiment_data GROUP BY country;

/*Mismatch Validation*/
SELECT COUNT(*) AS mismatches
FROM experiment_data
WHERE
(con_treat='control' AND page='new_page')
OR
(con_treat='treatment' AND page='old_page');

/*Country Winner Analysis*/
SELECT
country,
CASE
WHEN AVG(CASE
WHEN con_treat='treatment'
THEN converted
END)
>
AVG(CASE
WHEN con_treat='control'
THEN converted
END)
THEN 'Treatment Wins'
ELSE 'Control Wins'
END AS winner
FROM experiment_data
GROUP BY country;

/*Final Experiment Report View*/
CREATE VIEW final_experiment_report AS
SELECT
country,
con_treat,
COUNT(*) AS users,
SUM(converted) AS conversions,
ROUND(
AVG(converted)*100,
2
) AS conversion_rate
FROM experiment_data
GROUP BY country, con_treat;
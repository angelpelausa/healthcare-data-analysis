CREATE DATABASE hospital_db;

USE hospital_db;

CREATE TABLE encounters (
    Id VARCHAR(50),
    START VARCHAR(50),
    STOP VARCHAR(50),
    PATIENT VARCHAR(50),
    ORGANIZATION VARCHAR(50),
    PAYER VARCHAR(50),
    ENCOUNTERCLASS VARCHAR(50),
    CODE VARCHAR(50),
    DESCRIPTION TEXT,
    BASE_ENCOUNTER_COST VARCHAR(50),
    TOTAL_CLAIM_COST VARCHAR(50),
    PAYER_COVERAGE VARCHAR(50),
    REASONCODE VARCHAR(50),
    REASONDESCRIPTION TEXT
);

CREATE TABLE patients (
    Id VARCHAR(50),
    BIRTHDATE VARCHAR(50),
    DEATHDATE VARCHAR(50),
    PREFIX VARCHAR(50),
    FIRST VARCHAR(50),
    LAST VARCHAR(50),
    SUFFIX VARCHAR(50),
    MAIDEN VARCHAR(50),
    MARITAL VARCHAR(50),
    RACE VARCHAR(50),
    ETHNICITY VARCHAR(50),
    GENDER VARCHAR(50),
    BIRTHPLACE VARCHAR(50),
    ADDRESS TEXT,
    CITY VARCHAR(50),
    STATE VARCHAR(50),
    COUNTY VARCHAR(50),
    ZIP VARCHAR(50),
    LAT VARCHAR(50),
    LON VARCHAR(50)
);

CREATE TABLE organizations (
    Id VARCHAR(50),
    NAME VARCHAR(255),
    ADDRESS TEXT,
    CITY VARCHAR(100),
    STATE VARCHAR(10),
    ZIP VARCHAR(10),
    LAT VARCHAR(50),
    LON VARCHAR(50)
);

CREATE TABLE payers (
    Id VARCHAR(50),
    NAME VARCHAR(255),
    ADDRESS TEXT,
    CITY VARCHAR(100),
    STATE_HEADQUARTERED VARCHAR(10),
    ZIP VARCHAR(10),
    PHONE VARCHAR(20)
);

CREATE TABLE procedures (
    START VARCHAR(50),
    STOP VARCHAR(50),
    PATIENT VARCHAR(50),
    ENCOUNTER VARCHAR(50),
    CODE VARCHAR(50),
    DESCRIPTION TEXT,
    BASE_COST VARCHAR(50),
    REASONCODE VARCHAR(50),
    REASONDESCRIPTION TEXT
);

update encounters 
set start = replace(replace(start, 'T', ' '), 'Z', ''),
    stop = replace(replace(stop, 'T', ' '), 'Z', '');
    
-- convert to proper data types
alter table encounters 
modify start datetime,
modify stop datetime,
modify base_encounter_cost decimal(10,2),
modify total_claim_cost decimal(10,2),
modify payer_coverage decimal(10,2);

describe encounters;

select birthdate, deathdate from patients limit 5;

-- set empty deathdates to null for alive patients
update patients set deathdate = null where deathdate = '';

-- convert patients table dates and coordinates
alter table patients 
modify birthdate date,
modify deathdate date,
modify lat decimal(10,6),
modify lon decimal(10,6);

-- convert organizations coordinates to decimal
alter table organizations 
modify lat decimal(10,6),
modify lon decimal(10,6);

describe organizations;

update procedures 
set start = replace(replace(start, 'T', ' '), 'Z', ''),
    stop = replace(replace(stop, 'T', ' '), 'Z', '');
    
-- convert procedures table data types
alter table procedures 
modify start datetime,
modify stop datetime,
modify base_cost decimal(10,2);

describe procedures;

-- check for missing critical values
select count(*) as missing_patient from encounters where patient is null;
select count(*) as missing_start from encounters where start is null;

-- check for invalid dates
select count(*) as invalid_dates from encounters where stop < start;
select count(*) as invalid_birthdates from patients where deathdate < birthdate;

-- check for duplicate records
select id, count(*) from encounters group by id having count(*) > 1;

-- check for negative costs
select count(*) as negative_costs from encounters where base_encounter_cost < 0 or total_claim_cost < 0 or payer_coverage < 0;

-- check latitude and longitude ranges (should be reasonable for boston area)
select 
    min(lat) as min_lat, max(lat) as max_lat,
    min(lon) as min_lon, max(lon) as max_lon
from patients;

-- check encounters without matching patients
select count(*) as orphaned_encounters 
from encounters e 
left join patients p on e.patient = p.id 
where p.id is null;

-- check what encounter classes exist
select distinct encounterclass from encounters;

-- check what gender codes exist
select distinct gender from patients;

-- check what marital status codes exist
select distinct marital from patients;

-- check if payer coverage ever exceeds total claim cost
select count(*) as invalid_coverage 
from encounters 
where payer_coverage > total_claim_cost;

-- check if any procedures don't have matching encounters
select count(*) as orphaned_procedures
from procedures p
left join encounters e on p.encounter = e.id
where e.id is null;

-- check if stop dates are null for ongoing encounters
select count(*) as null_stop_dates from encounters where stop is null;

-- check for extreme cost values that might be errors
select 
    min(base_encounter_cost) as min_base_cost,
    max(base_encounter_cost) as max_base_cost,
    min(total_claim_cost) as min_claim_cost, 
    max(total_claim_cost) as max_claim_cost
from encounters;

-- check the extreme high cost records
select id, base_encounter_cost, total_claim_cost, payer_coverage, encounterclass
from encounters 
where total_claim_cost > 100000
order by total_claim_cost desc
limit 10;

-- check if there are any zero cost encounters
select count(*) as zero_cost_encounters
from encounters 
where total_claim_cost = 0;

-- examine zero cost encounters
select encounterclass, payer, count(*) as count
from encounters 
where total_claim_cost = 0
group by encounterclass, payer;

-- check payer names for zero cost encounters
select p.name as payer_name, count(*) as zero_cost_count
from encounters e
left join payers p on e.payer = p.id
where e.total_claim_cost = 0
group by p.name
order by zero_cost_count desc;

-- check patient ages are reasonable
select 
    min(birthdate) as oldest_birthdate,
    max(birthdate) as youngest_birthdate
from patients;

-- kpi analysis

-- total encounters by year
select year(start) as year, count(*) as total_encounters
from encounters 
group by year(start)
order by year;

-- encounter class percentages by year
select 
    year(start) as year,
    encounterclass,
    count(*) as count,
    round((count(*) * 100.0 / sum(count(*)) over (partition by year(start))), 2) as percentage
from encounters 
group by year(start), encounterclass
order by year, percentage desc;

-- encounters over 24 hours vs under 24 hours
select 
    case when timestampdiff(hour, start, stop) > 24 then 'over 24 hours'
         else 'under 24 hours' end as duration_category,
    count(*) as count,
    round((count(*) * 100.0 / (select count(*) from encounters)), 2) as percentage
from encounters 
where stop is not null
group by duration_category;

-- encounters with zero payer coverage
select 
    count(*) as zero_coverage_count,
    round((count(*) * 100.0 / (select count(*) from encounters)), 2) as percentage
from encounters 
where payer_coverage = 0 or payer_coverage is null;

-- top 10 most frequent procedures and average cost
select 
    description,
    count(*) as procedure_count,
    round(avg(base_cost), 2) as avg_cost
from procedures
group by description
order by procedure_count desc
limit 10;

-- top 10 procedures with highest average cost (minimum 5 occurrences)
select 
    description,
    count(*) as procedure_count,
    round(avg(base_cost), 2) as avg_cost
from procedures
group by description
having count(*) >= 5
order by avg_cost desc
limit 10;

-- average total claim cost by payer
select 
    p.name as payer_name,
    count(*) as encounter_count,
    round(avg(e.total_claim_cost), 2) as avg_claim_cost
from encounters e
left join payers p on e.payer = p.id
group by p.name
order by avg_claim_cost desc;

-- unique patients per quarter over time
select 
    year(start) as year,
    quarter(start) as quarter,
    count(distinct patient) as unique_patients
from encounters 
group by year(start), quarter(start)
order by year, quarter;

-- patients readmitted within 30 days
with patient_encounters as (
    select 
        patient,
        start,
        lag(stop) over (partition by patient order by start) as previous_stop
    from encounters
)
select count(distinct patient) as readmitted_patients
from patient_encounters
where previous_stop is not null 
  and datediff(start, previous_stop) <= 30;
  
  -- top 10 patients with most readmissions
with readmissions as (
    select 
        patient,
        start,
        lag(stop) over (partition by patient order by start) as previous_stop,
        case when lag(stop) over (partition by patient order by start) is not null 
             and datediff(start, lag(stop) over (partition by patient order by start)) <= 30 
             then 1 else 0 end as is_readmission
    from encounters
)
select 
    concat(p.first, ' ', p.last) as patient_name,
    count(*) as total_encounters,
    sum(is_readmission) as readmission_count,
    round((sum(is_readmission) * 100.0 / count(*)), 2) as readmission_rate
from readmissions r
join patients p on r.patient = p.id
group by r.patient, p.first, p.last
having readmission_count > 0
order by readmission_count desc
limit 10;

-- KPI 1: Encounters by year
CREATE VIEW kpi_encounters_by_year AS
SELECT YEAR(start) AS year, COUNT(*) AS total_encounters
FROM encounters 
GROUP BY YEAR(start)
ORDER BY year;

-- KPI 2: Encounter class distribution by year
CREATE VIEW kpi_encounter_classes AS
SELECT 
    YEAR(start) AS year,
    encounterclass,
    COUNT(*) AS count,
    ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY YEAR(start))), 2) AS percentage
FROM encounters 
GROUP BY YEAR(start), encounterclass
ORDER BY year, percentage DESC;

-- KPI 3: Encounter duration analysis
CREATE VIEW kpi_encounter_duration AS
SELECT 
    CASE WHEN TIMESTAMPDIFF(HOUR, start, stop) > 24 THEN 'over 24 hours'
         ELSE 'under 24 hours' END AS duration_category,
    COUNT(*) AS count,
    ROUND((COUNT(*) * 100.0 / (SELECT COUNT(*) FROM encounters)), 2) AS percentage
FROM encounters 
WHERE stop IS NOT NULL
GROUP BY duration_category;

-- KPI 4: Zero coverage encounters
CREATE VIEW kpi_zero_coverage AS
SELECT 
    COUNT(*) AS zero_coverage_count,
    ROUND((COUNT(*) * 100.0 / (SELECT COUNT(*) FROM encounters)), 2) AS percentage
FROM encounters 
WHERE payer_coverage = 0 OR payer_coverage IS NULL;

-- KPI 5: Most frequent procedures
CREATE VIEW kpi_frequent_procedures AS
SELECT 
    description,
    COUNT(*) AS procedure_count,
    ROUND(AVG(base_cost), 2) AS avg_cost
FROM procedures
GROUP BY description
ORDER BY procedure_count DESC
LIMIT 10;

-- KPI 6: Most expensive procedures
CREATE VIEW kpi_expensive_procedures AS
SELECT 
    description,
    COUNT(*) AS procedure_count,
    ROUND(AVG(base_cost), 2) AS avg_cost
FROM procedures
GROUP BY description
HAVING COUNT(*) >= 5
ORDER BY avg_cost DESC
LIMIT 10;

-- KPI 7: Average cost by payer
CREATE VIEW kpi_cost_by_payer AS
SELECT 
    p.name AS payer_name,
    COUNT(*) AS encounter_count,
    ROUND(AVG(e.total_claim_cost), 2) AS avg_claim_cost
FROM encounters e
LEFT JOIN payers p ON e.payer = p.id
GROUP BY p.name
ORDER BY avg_claim_cost DESC;

-- KPI 8: Unique patients per quarter
CREATE VIEW kpi_patients_per_quarter AS
SELECT 
    YEAR(start) AS year,
    QUARTER(start) AS quarter,
    COUNT(DISTINCT patient) AS unique_patients
FROM encounters 
GROUP BY YEAR(start), QUARTER(start)
ORDER BY year, quarter;

-- KPI 9: 30-day readmissions count
CREATE VIEW kpi_readmissions_count AS
WITH patient_encounters AS (
    SELECT 
        patient,
        start,
        LAG(stop) OVER (PARTITION BY patient ORDER BY start) AS previous_stop
    FROM encounters
)
SELECT COUNT(DISTINCT patient) AS readmitted_patients
FROM patient_encounters
WHERE previous_stop IS NOT NULL 
  AND DATEDIFF(start, previous_stop) <= 30;

-- KPI 10: Top patients with most readmissions
CREATE VIEW kpi_top_readmitted_patients AS
WITH readmissions AS (
    SELECT 
        patient,
        start,
        LAG(stop) OVER (PARTITION BY patient ORDER BY start) AS previous_stop,
        CASE WHEN LAG(stop) OVER (PARTITION BY patient ORDER BY start) IS NOT NULL 
             AND DATEDIFF(start, LAG(stop) OVER (PARTITION BY patient ORDER BY start)) <= 30 
             THEN 1 ELSE 0 END AS is_readmission
    FROM encounters
)
SELECT 
    CONCAT(p.first, ' ', p.last) AS patient_name,
    COUNT(*) AS total_encounters,
    SUM(is_readmission) AS readmission_count,
    ROUND((SUM(is_readmission) * 100.0 / COUNT(*)), 2) AS readmission_rate
FROM readmissions r
JOIN patients p ON r.patient = p.id
GROUP BY r.patient, p.first, p.last
HAVING readmission_count > 0
ORDER BY readmission_count DESC
LIMIT 10;

SHOW TABLES LIKE 'kpi_%';
SELECT * FROM hr_raw;

SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME   = 'hr_raw'
  AND TABLE_SCHEMA = 'dbo'   
ORDER BY ORDINAL_POSITION;

/* RAW, STAGING */
-- Row count and basic shape
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT Employee_ID) AS unique_employees,
       MIN(Hire_Date) AS earliest_hire,
       MAX(Hire_Date) AS latest_hire,
       COUNT(DISTINCT Country) AS countries,
       COUNT(DISTINCT Department) AS departments
FROM hr_raw;

-- Null rate per column
SELECT
  100.0 * SUM(CASE WHEN Employee_ID IS NULL THEN 1 END) / COUNT(*) AS pct_null_id,
  100.0 * SUM(CASE WHEN Full_Name IS NULL THEN 1 END) / COUNT(*) AS pct_null_name,
  100.0 * SUM(CASE WHEN Department IS NULL THEN 1 END) / COUNT(*) AS pct_null_dep,
  100.0 * SUM(CASE WHEN Job_Title IS NULL THEN 1 END) / COUNT(*) AS pct_null_job_title,
  100.0 * SUM(CASE WHEN Hire_Date IS NULL THEN 1 END) / COUNT(*) AS pct_null_hire,
  100.0 * SUM(CASE WHEN Performance_Rating IS NULL THEN 1 END) / COUNT(*) AS pct_null_rating,
  100.0 * SUM(CASE WHEN Experience_Years IS NULL THEN 1 END) / COUNT(*) AS pct_null_exp,
  100.0 * SUM(CASE WHEN Status IS NULL THEN 1 END) / COUNT(*) AS pct_null_status,
  100.0 * SUM(CASE WHEN Work_Mode IS NULL THEN 1 END) / COUNT(*) AS pct_null_work_mode,
  100.0 * SUM(CASE WHEN Salary IS NULL THEN 1 END) / COUNT(*) AS pct_null_salary,
  100.0 * SUM(CASE WHEN Year IS NULL THEN 1 END) / COUNT(*) AS pct_null_year,
  100.0 * SUM(CASE WHEN Country IS NULL THEN 1 END) / COUNT(*) AS pct_null_country,
  100.0 * SUM(CASE WHEN City IS NULL THEN 1 END) / COUNT(*) AS pct_null_city,
  100.0 * SUM(CASE WHEN Age IS NULL THEN 1 END) / COUNT(*) AS pct_null_age,
  100.0 * SUM(CASE WHEN Job_Level IS NULL THEN 1 END) / COUNT(*) AS pct_null_job_level
FROM hr_raw;

-- Distinct values for categoricals
SELECT Department, COUNT(*) AS n FROM hr_raw
GROUP BY Department
ORDER BY n DESC;

SELECT Performance_Rating, COUNT(*) AS n FROM hr_raw
GROUP BY Performance_Rating
ORDER BY n DESC;

SELECT Status, COUNT(*) AS n FROM hr_raw
GROUP BY Status
ORDER BY n DESC;

SELECT Work_Mode, COUNT(*) AS n FROM hr_raw
GROUP BY Work_Mode
ORDER BY n DESC;

SELECT Country, COUNT(*) AS n FROM hr_raw
GROUP BY Country
ORDER BY n DESC;

SELECT Job_Level, COUNT(*) AS n FROM hr_raw
GROUP BY Job_Level
ORDER BY n DESC;

-- Numeric columns distribution
WITH num_col_dis AS (
    SELECT
        MIN(Salary) OVER() AS min_salary,
        MAX(Salary) OVER() AS max_salary,
        ROUND(AVG(Salary) OVER(), 2) AS avg_salary,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Salary) OVER() AS median_salary,
        MIN(Age) OVER() AS min_age,
        MAX(Age) OVER() AS max_age,
        MIN(Experience_Years) OVER() AS min_exp,
        MAX(Experience_Years) OVER() AS max_exp
    FROM hr_raw
)
SELECT DISTINCT * FROM num_col_dis;

-- Detect duplicate primary key
SELECT Employee_ID, COUNT(*) AS occurrences FROM hr_raw
GROUP BY Employee_ID
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;

-- Detect future hire date
SELECT Employee_ID, Full_Name, Hire_Date FROM hr_raw
WHERE Hire_Date > GETDATE()
ORDER BY Hire_Date;

-- Validate year column matches hire date year
SELECT Employee_ID, Hire_Date, Year
FROM hr_raw
WHERE YEAR(Hire_Date) <> Year;

-- Dectect duplicate names
WITH a AS 
(
    SELECT Full_Name, COUNT(Full_Name) AS counts FROM hr_raw
    GROUP BY Full_Name
    HAVING COUNT(Full_Name) > 1
)
SELECT * FROM hr_raw hr
JOIN a ON a.Full_Name = hr.Full_Name
ORDER BY hr.Full_Name;

/* VALUE VALIDATION */
-- Flag impossible age/experience combinations
SELECT Employee_ID, Full_Name, Age, Experience_Years
FROM hr_raw
WHERE Experience_Years > (Age - 18)
   OR Age < 18
   OR Experience_Years < 0;

-- Flag title/level mismatch
SELECT Employee_ID, Full_Name, Job_Title, Job_Level, Salary
FROM hr_raw
WHERE Job_Level = 'Junior'
  AND (
    Job_Title LIKE '%Director%'
    OR Job_Title LIKE '%CFO%'
    OR Job_Title LIKE '%Chief%'
    OR Job_Title LIKE '%VP%'
  );

-- Salary outlier detection (z-score method) 
WITH stats AS (
  SELECT Job_Level,
    AVG(Salary)    AS mean_sal,
    STDEV(Salary) AS std_sal
  FROM hr_raw
  GROUP BY Job_Level
)
SELECT e.Employee_ID, e.Full_Name, e.Job_Level,
       e.Salary, s.mean_sal,
       ROUND(ABS(e.Salary - s.mean_sal) / NULLIF(s.std_sal, 0), 2) AS z_score
FROM hr_raw e
JOIN stats s ON s.Job_Level = e.Job_Level
WHERE ABS(e.Salary - s.mean_sal) / NULLIF(s.std_sal, 0) > 3
ORDER BY z_score DESC;

  /* CLEANING */
-- Fill nulls with a default value
UPDATE hr_raw
SET
    Salary = COALESCE(Salary, 0),
    Performance_Rating = COALESCE(Performance_Rating, 'Unknown')
WHERE Salary IS NULL
   OR Performance_Rating IS NULL;

-- Update Experience_Years = Current year - Hire year
UPDATE hr_raw
SET Experience_Years =
    DATEDIFF(YEAR, Hire_Date, GETDATE())
    - CASE
        WHEN DATEADD(YEAR,
                     DATEDIFF(YEAR, Hire_Date, GETDATE()),
                     Hire_Date) > GETDATE()
        THEN 1
        ELSE 0
      END
WHERE Hire_Date IS NOT NULL;

ALTER TABLE hr_raw
ALTER COLUMN Experience_Years SMALLINT NOT NULL;

-- Strip honorifics from Full_Name
UPDATE hr_raw
SET
    Full_Name = TRIM(REGEXP_REPLACE(Full_Name, '^(Mr.?|Mrs.?|Ms.?|Miss.?|Dr.?|Prof.?|Univ.Prof.?|Dipl.-Ing.?|Sig.ra.?)\s+', ''))
FROM hr_raw;

-- Strip name suffixes (MBA, B.Sc., II etc.)
UPDATE hr_raw
SET
    Full_Name = TRIM(REGEXP_REPLACE(Full_Name, 's+(MBA.?|B.Sc.?|B.A.?|B.Eng.?|II|III|Jr.?|Sr.?)$', ''))
FROM hr_raw;

-- Standardise casing & trim whitespace
UPDATE hr_raw
SET
    Full_Name = TRIM(Full_Name),
    Department = LOWER(TRIM(Department)),
    Job_Title = LOWER(TRIM(Job_Title)),
    Performance_Rating = LOWER(TRIM(Performance_Rating)),
    Status = LOWER(TRIM(Status)),
    Work_Mode = LOWER(TRIM(Work_Mode)),
    Country = LOWER(TRIM(Country)),
    City = LOWER(TRIM(City)),
    Job_Level = LOWER(TRIM(Job_Level))
FROM hr_raw;

/* CREATE QUARANTINE SCHEMA FOR FLAGGED RECORDS */
CREATE SCHEMA quarantine;

CREATE TABLE quarantine.employees 
(
    Quarantine_ID INT IDENTITY(1, 1) PRIMARY KEY,
    Employee_ID VARCHAR(50) NOT NULL,
    Full_name VARCHAR(50) NOT NULL,
    error_reason VARCHAR(100) NOT NULL,
    failed_at DATETIME NOT NULL
);

INSERT INTO quarantine.employees (Employee_ID, Full_Name, error_reason, failed_at)
SELECT 
    Employee_ID, Full_Name,
    CONCAT(
        CASE 
            WHEN Salary <= 0 
            THEN 'invalid_salary; ' 
            ELSE '' 
        END,
        CASE 
            WHEN Performance_Rating = 'unknown' 
            THEN 'invalid_performance_rating; ' 
            ELSE '' 
        END,
        CASE 
            WHEN Experience_Years < 0 
            THEN 'invalid_experience_year; ' 
            ELSE '' 
        END,
        CASE 
            WHEN Job_Level = 'Junior' 
                AND (Job_Title LIKE '%Director%'
                    OR Job_Title LIKE '%CFO%'
                    OR Job_Title LIKE '%Chief%'
                    OR Job_Title LIKE '%VP%')
            THEN 'check position and level'
            ELSE ''
        END
    ) AS error_reason,
    GETDATE()
FROM hr_raw
WHERE Performance_Rating = 'unknown'
    OR Salary <= 0
    OR Experience_Years < 0;

SELECT * FROM quarantine.employees;
DROP TABLE quarantine.employees;

/* CREATE CLEAN SCHEMA FOR CLEAN TABLE */
CREATE SCHEMA clean;

CREATE TABLE clean.employees
(
    Employee_ID VARCHAR(50) PRIMARY KEY,
    Full_Name VARCHAR(100) NOT NULL,
    Department VARCHAR(50) NOT NULL,
    Job_Title VARCHAR(50) NOT NULL,
    Hire_Date DATE NOT NULL,
    Performance_Rating VARCHAR(50) NOT NULL,
    Experience_Years SMALLINT NOT NULL,
    Status VARCHAR(50) NOT NULL,
    Work_Mode VARCHAR(50) NOT NULL,
    Salary INT NOT NULL,
    Year SMALLINT NOT NULL,
    Country VARCHAR(50) NOT NULL,
    City VARCHAR(50) NOT NULL,
    Age SMALLINT NOT NULL,
    Job_Level VARCHAR(50) NOT NULL
);

INSERT INTO clean.employees
SELECT Employee_ID, 
    Full_Name, 
    Department, 
    Job_Title,
    Hire_Date, 
    Performance_Rating, 
    Experience_Years, 
    Status,
    Work_Mode, 
    Salary,
    Year, 
    Country, 
    City, 
    Age, 
    Job_Level
FROM hr_raw hr
WHERE NOT EXISTS (
    SELECT 1
    FROM quarantine.employees q
    WHERE q.Employee_ID = hr.Employee_ID
);

SELECT * FROM clean.employees;
DROP TABLE clean.employees;

/* CREATE FACT AND DIMS TABLES */
-- Fact table (employee_snapshot)
CREATE TABLE employee_snapshot
(
    Employee_ID VARCHAR(50) PRIMARY KEY,
    Department_ID INT NOT NULL,
    Location_ID INT NOT NULL,
    Salary INT NOT NULL,
    Performance_Rating VARCHAR(50) NOT NULL,
    Experience_Years SMALLINT NOT NULL,
    Work_Mode VARCHAR(50) NOT NULL,
    Hire_Year SMALLINT NOT NULL
);

-- Dim tables (employee, department, location)
CREATE TABLE employee
(
    Employee_ID VARCHAR(50) PRIMARY KEY,
    Full_Name VARCHAR(100) NOT NULL,
    Age SMALLINT NOT NULL,
    Job_Title VARCHAR(50) NOT NULL,
    Job_Level VARCHAR(50) NOT NULL,
    Hire_Date DATE NOT NULL,
    Status VARCHAR(50) NOT NULL
);

CREATE TABLE department
(
    Department_ID INT IDENTITY(1, 1) PRIMARY KEY,
    Department VARCHAR(50) UNIQUE
);

CREATE TABLE location
(
    Location_ID INT IDENTITY(1, 1) PRIMARY KEY,
    Country VARCHAR(50) NOT NULL,
    City VARCHAR(50) NOT NULL,
    UNIQUE (Country, City)
);

-- Insert data into new tables
INSERT INTO department (Department)
SELECT DISTINCT ce.Department FROM clean.employees ce
ORDER BY ce.Department;

INSERT INTO location (Country, City)
SELECT DISTINCT ce.Country, ce.City FROM clean.employees ce
ORDER BY ce.Country, ce.City;

INSERT INTO employee (Employee_ID, Full_Name, Age, Job_Title, Job_Level, Hire_Date, Status)
SELECT ce.Employee_ID, ce.Full_Name, ce.Age, ce.Job_Title, ce.Job_Level, ce.Hire_Date, ce.Status
FROM clean.employees ce;

INSERT INTO employee_snapshot (Employee_ID, Department_ID, Location_ID, Salary, Performance_Rating, Experience_Years, Work_Mode, Hire_Year)
SELECT ce.Employee_ID, d.Department_ID, l.Location_ID, ce.Salary, ce.Performance_Rating, ce.Experience_Years, ce.Work_Mode, ce.Year
FROM clean.employees ce
JOIN department d ON d.Department = ce.Department
JOIN location l ON l.Country = ce.Country AND l.City = ce.City;

SELECT * FROM employee_snapshot;
SELECT * FROM employee;
SELECT * FROM department;
SELECT * FROM location;
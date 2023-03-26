---------------------------------------
-- TASK 1. Create table for our raw data 
---------------------------------------
DROP TABLE raw_data;
CREATE TABLE raw_data(
	--id SERIAL,
	institution_code VARCHAR(255), 
	institution_name VARCHAR(255),
	institution_sort_order INT,
	main_panel VARCHAR(255),
	unit_of_assessment_number INT,
	unit_of_assessment_name VARCHAR(255),
	multiple_submission_letter VARCHAR(255),
	multiple_submission_name VARCHAR(255),
	joint_submission VARCHAR(255),
	profile VARCHAR(255),
	FTE_category_A_staff_submitted NUMERIC (5,2),
	star_rating VARCHAR(255),
	percentage VARCHAR(255)
);

-- import data (run from psql):
-- \copy raw_data FROM 'C:\Users\...filepath...\raw_data.csv' WITH CSV HEADER;
-- This is just a test

-- add primary key:
ALTER TABLE raw_data ADD COLUMN id SERIAL PRIMARY KEY;

-------------------------------------------
-- TASK 2: Data cleaning
-------------------------------------------
-- some exploratory queries:  
SELECT * FROM raw_data LIMIT 5;
SELECT COUNT(*) FROM raw_data;
-- select rows in this column which do not have numeric values: 
SELECT institution_code, id FROM raw_data WHERE institution_code !~ '^([0-9]+[.]?[0-9]*|[.][0-9]+)$'; 
SELECT percentage, id FROM raw_data WHERE percentage !~ '^([0-9]+[.]?[0-9]*|[.][0-9]+)$'; 
SELECT star_rating FROM raw_data WHERE star_rating !~ '^([0-9]+[.]?[0-9]*|[.][0-9]+)$'; 

-- duplicate the raw_data table (this is the one we will work on)
DROP TABLE IF EXISTS ref_table;
CREATE TABLE ref_table AS (SELECT * FROM raw_data);

-- remove unwanted characters and change types: 
UPDATE ref_table SET institution_code = REGEXP_REPLACE(institution_code, '[^0-9]+', '', 'g')
UPDATE ref_table SET institution_code = NULLIF(institution_code, '');
ALTER TABLE ref_table ALTER COLUMN institution_code TYPE INT USING institution_code::integer;

UPDATE ref_table SET percentage = REGEXP_REPLACE(percentage, '[^0-9.]+', '', 'g'); -- (note the . in the regex. We don't want to delete any decimal points)
UPDATE ref_table SET percentage = NULLIF(percentage, '');
ALTER TABLE ref_table ALTER COLUMN percentage TYPE NUMERIC(4,1) USING percentage::numeric(4,1);

-------------------------------------------
-- TASK 3: Data exploration
-------------------------------------------

-- Q1: which are the best institutions in terms of research? List top 5 that scored the highest in terms of grades 4* and 3*.

SELECT institution_name, ROUND(AVG(percentage),2) FROM ref_table 
	WHERE profile='Overall' AND (star_rating='4*' OR star_rating='3*') GROUP BY institution_name ORDER BY AVG(percentage) DESC LIMIT 30;


-- Q2: how many FTE (full-time equivalent) staff were there in total?

SELECT ROUND(SUM(a.total)::numeric, 2) "Total FTE staff"
FROM (SELECT AVG(FTE_category_A_staff_submitted) as total FROM ref_table 
		GROUP BY institution_name, unit_of_assessment_name, FTE_category_A_staff_submitted, multiple_submission_name
		ORDER BY institution_name, unit_of_assessment_name) a;


-- Q3: which institutions scored the highest 4* ratings for philosophy?

CREATE OR REPLACE FUNCTION get_table(uoa varchar(255))
	returns table (
		institution_name VARCHAR(255),
		unit_of_assessment_name VARCHAR(255), 
		profile VARCHAR(255), 
		star_rating VARCHAR(255), 
		percentage NUMERIC(4,1)) 
	language plpgsql
	as $$
	#variable_conflict use_column
	begin
		return query
		SELECT 	institution_name, 
				unit_of_assessment_name, 
				profile, star_rating, 
				percentage 
		FROM ref_table 
		WHERE unit_of_assessment_name=uoa OR uoa is null
			GROUP BY unit_of_assessment_name, institution_name, 
				multiple_submission_name, profile, star_rating, percentage 
			ORDER BY institution_name;
	end;
	$$;

SELECT 	a.institution_name as "Institution name", 
		a.percentage as "Overall quality profile"
FROM (
		SELECT *  FROM get_table('Philosophy')
) AS a 
WHERE a.profile='Overall' AND a.star_rating='4*' ORDER BY a.percentage DESC;


-- Q4: Which institution scored highest for philosophy in terms of both 4* and 3*?

CREATE VIEW UOA_table AS
SELECT 	institution_name, 
		unit_of_assessment_name, 
		profile, 
		star_rating, 
		percentage 
FROM ref_table 
WHERE unit_of_assessment_name='Philosophy' 
	GROUP BY unit_of_assessment_name, institution_name, multiple_submission_name, 
		profile, star_rating, percentage ORDER BY institution_name;

SELECT 	a.institution_name as "Institution name", 
		ROUND(AVG(a.percentage),2) as "Overall quality profile"
FROM (SELECT * FROM UOA_table) AS a 
WHERE a.profile='Overall' AND (a.star_rating='4*' OR a.star_rating='3*') 
	GROUP BY a.institution_name ORDER BY "Overall quality profile" DESC;


-- Q5: Give the rankings in terms of ‘research power’.

-- view 
CREATE OR REPLACE VIEW gpa_table AS
SELECT 
	institution_name, 
	unit_of_assessment_name, 
	multiple_submission_name, 
	FTE_category_A_staff_submitted as fte,
	profile,
	ROUND(SUM(a.gpa)/100,2) as overall_gpa -- add the GPAs together and divide by 100 
FROM (SELECT 
		institution_name, 
		unit_of_assessment_name, 
		multiple_submission_name, 
	  	FTE_category_A_staff_submitted,
		profile,
		star_rating,
		percentage,	  	
		CASE -- multiply the percentage for each atar rating by its star rating:
			WHEN star_rating = '4*' THEN percentage*4	
			WHEN star_rating = '3*' THEN percentage*3	
			WHEN star_rating = '2*' THEN percentage*2	
			WHEN star_rating = '1*' THEN percentage*1	
			ELSE percentage*0
		END AS gpa
	FROM ref_table 
	WHERE profile='Overall'
		GROUP BY institution_name, unit_of_assessment_name, multiple_submission_name, 
	  		FTE_category_A_staff_submitted, profile, star_rating, percentage
	) as a 
	GROUP BY institution_name, unit_of_assessment_name, 
		multiple_submission_name, FTE_category_A_staff_submitted, profile;

-- query
SELECT 
	ROW_NUMBER() OVER(ORDER BY SUM(fte*overall_gpa) DESC) "result", -- show numbers next to results
	institution_name, 
	ROUND((SUM(fte*overall_gpa)/SUM(fte)),2) as fte_weighted_gpa, -- for each oua, multiply the GPA by its FTE. Then add the results and divide by the total ftes in that institution.
	SUM(fte) as "total fte in uni",
	SUM(fte*overall_gpa) as "SUM of fte * overall_gpa",
	SUM(overall_gpa) as "overall gpa"	
FROM (SELECT * FROM gpa_table) AS a
GROUP BY institution_name
ORDER BY "SUM of fte * overall_gpa" DESC;

-- Q6: Which units of assessment had the highest submission counts?

WITH a AS (
	SELECT 	unit_of_assessment_name, 
			unit_of_assessment_number, 
			multiple_submission_name, 
			institution_name 
	FROM ref_table
		GROUP BY institution_name, unit_of_assessment_name, unit_of_assessment_number, 
			multiple_submission_name ORDER BY unit_of_assessment_name, institution_name
) SELECT unit_of_assessment_number, 
		unit_of_assessment_name, 
		COUNT(unit_of_assessment_name) as "Number of submissions"
FROM a
	GROUP BY unit_of_assessment_name, unit_of_assessment_number 
	ORDER BY "Number of submissions" DESC;

-------------------------------------------
-- TASK 4: Import new data
-------------------------------------------

-- 1. Create a table with the relevant data types

DROP TABLE raw_data_context;
CREATE TABLE raw_data_context(
	instid INT, 
	ukprn INT,
	region VARCHAR(255),
	he_provider VARCHAR(255),
	unit_of_assessment_number VARCHAR(255),-- change this 
	unit_of_assessment_name VARCHAR(255),
	multiple_submission_letter VARCHAR(255),
	FTE_scaled VARCHAR(255) -- change this 
);

-- 2. download data and import from local drive. Run via psql:
--'\copy raw_data_context FROM 'C:/Users/...filepath.../raw_data_context.csv' WITH CSV HEADER;'



-- 3. clean data 
UPDATE raw_data_context SET unit_of_assessment_number = REGEXP_REPLACE(unit_of_assessment_number, '[^0-9]+', '00', 'g')
ALTER TABLE raw_data_context ALTER COLUMN unit_of_assessment_number TYPE INT USING unit_of_assessment_number::integer;

UPDATE raw_data_context SET FTE_scaled = REGEXP_REPLACE(FTE_scaled, '[^0-9]+', '0', 'g')
ALTER TABLE raw_data_context ALTER COLUMN FTE_scaled TYPE INT USING FTE_scaled::integer;

-- create temp tables:

-- table 1 
CREATE TEMPORARY TABLE fte_submitted AS 
WITH a AS 
(SELECT institution_code, 
 		institution_name,
 		ROUND(AVG(FTE_category_A_staff_submitted),2) as fte, 
 		unit_of_assessment_number, 
 		multiple_submission_name
FROM ref_table
	GROUP BY institution_code, institution_name,  unit_of_assessment_number, multiple_submission_name 
	ORDER BY institution_name, unit_of_assessment_number, multiple_submission_name
)
SELECT
	  institution_code, 
	  institution_name, 
	  SUM(fte) as "Submitted FTE" 
FROM a 
	GROUP BY institution_code, institution_name 
	ORDER BY institution_code;

-- table 2
CREATE TEMPORARY TABLE fte_eligible AS 
SELECT 	ukprn, 
		SUM(FTE_scaled) as "Eligible FTE" 
FROM raw_data_context 
	GROUP BY ukprn ORDER BY ukprn;
	
-- Join the two tables 
SELECT 
	fte_submitted.institution_code,
	fte_submitted.institution_name,
	fte_submitted."Submitted FTE",  
	fte_eligible."Eligible FTE",
	ROUND(fte_submitted."Submitted FTE"/NULLIF(fte_eligible."Eligible FTE", 0),4) as "Intensity"
FROM fte_submitted 
INNER JOIN fte_eligible ON fte_submitted.institution_code = fte_eligible.ukprn
WHERE ROUND(fte_submitted."Submitted FTE"/NULLIF(fte_eligible."Eligible FTE", 0),4) <1  
	ORDER BY "Intensity" DESC;




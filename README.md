# Research Excellence Framework 2014 
## A SQL data exploration

The [UK University Research Excellence Framework Ratings 2014](https://public.tableau.com/s/sites/default/files/media/Resources/Research%20Excellence%20Framework%202014%20Results_Pivoted.xlsx) was conducted by the four UK higher education funding bodies in order to assess the quality of research in UK higher education institutions. The dataset contains data on 154 institutions, each of which made submissions for up to 36 'units of assessment' (e.g. history, philosophy, biological sciences, etc.) Each submission was graded in terms of the university's output, research environment and impact the research had on society in general. 

The purpose here is to answer a number of questions about the dataset using **PostgreSQL** to import and analyse the data. We shall rely primarily on **PgAdmin**, though a little is done in **psql** also. SQL skills utilised include: *creating tables, setting and converting data types, subquerying, user-defined functions, views, grouping data, temp tables, joins, CTEs, case statements and a number of mathematical aggregate functions.*    

## Understanding of the data

The data comes in the form of an Excel spreadsheet, which has been downloaded, converted to a .csv file and stored on a local drive. 

Below shows the format of the raw data: here we have one of our 154 institutions (*Anglia Ruskin*) and one of its submissions (*Allied Health Professions, Dentistry, Nursing and Pharmacy*). Each submission is broken into 4 'profiles' (*outputs, impact, environment* and *overall*) and each of these in turn is given a 'star rating' (from 4* to *unclassified*). The values for the ratings are stored in the percentage column, and sum to 100 for each profile. 

The better submissions will have higher values for 4* and 3* in each of the profiles. To simplify things, I focus only on the 'Overall' profile, which is the average of the other three profiles.   

![image](https://user-images.githubusercontent.com/86210945/151533542-42289c04-8680-408a-b959-2456d492c0f5.png)

## Task 1: create a table and import raw data into it 

First let's create a table with columns that match the columns we find in the .csv data. Two columns (institution_code and percentage) are initially set to varchar when really they should be INT and NUMERIC respectively. This is because (as it turns out) there are some non-numeric characters in those columns which cause errors when using numeric types. (We will resolve this shortly.)   

~~~~sql
DROP TABLE raw_data;
CREATE TABLE raw_data(
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
~~~~

In psql, we run the following  to import the data:

```console
\copy raw_data FROM 'C:\Users\Public\SQL_test_project\raw_data.csv' WITH CSV HEADER;
```

Let's see how many rows we have loaded:  
~~~~sql
SELECT COUNT(*) FROM raw_data;
~~~~

![image](https://user-images.githubusercontent.com/86210945/151538690-f0a344ef-cf2b-4210-98a7-a09c8d2ba8b5.png)

We can, if we like, add a primary key to the table: 
~~~~sql 
ALTER TABLE raw_data ADD COLUMN id SERIAL PRIMARY KEY;
~~~~

## Task 2: Data cleaning

We will work with a duplicate of the raw_data table, and make changes to that only: 

~~~~sql
CREATE TABLE ref_table AS (SELECT * FROM raw_data);
~~~~

As noted above, a couple of the columns which should have numeric data types have some non-numeric characters in them. We can see this by using a bit of regex:

~~~~sql
SELECT 	institution_code, 
	id 
FROM raw_data WHERE institution_code !~ '^([0-9]+[.]?[0-9]*|[.][0-9]+)$'; 
~~~~
![image](https://user-images.githubusercontent.com/86210945/151539222-1a480bf3-ed33-483e-97a0-eceb54b2d0e0.png)
...

We'll remove the offending characters by using REGEXP_REPLACE to replace them with a space, and then converting the spaces to NULL (this is because we won't be able to cast the type to a numeric with a space): 

~~~~sql
UPDATE ref_table SET institution_code = REGEXP_REPLACE(institution_code, '[^0-9]+', '', 'g')
UPDATE ref_table SET institution_code = NULLIF(institution_code, '');
ALTER TABLE ref_table ALTER COLUMN institution_code TYPE INT USING institution_code::integer;
~~~~

(We do similar for the other column)
~~~~sql
UPDATE ref_table SET percentage = REGEXP_REPLACE(percentage, '[^0-9.]+', '', 'g');
UPDATE ref_table SET percentage = NULLIF(percentage, '');
ALTER TABLE ref_table ALTER COLUMN percentage TYPE NUMERIC(4,1) USING percentage::numeric(4,1);
~~~~

## Task 3: data exploration 

We are now ready to run queries to answer questions about the data. 

#### Question 1: which are the best institutions in terms of research? List top 5 that scored the highest in terms of grades 4* and 3*.

~~~~sql
SELECT 	institution_name, 
	ROUND(AVG(percentage),2) 
FROM ref_table 
WHERE profile='Overall' AND (star_rating='4*' OR star_rating='3*') 
	GROUP BY institution_name ORDER BY AVG(percentage) DESC LIMIT 5;
~~~~

![image](https://user-images.githubusercontent.com/86210945/151784509-8dcb0fa4-d543-4e84-81e3-70a67f862f97.png)




#### Question 2: how many FTE (full-time equivalent) staff were there in total?  

Each submission had a given number of FTE staff, and so we need to add together the staff of every submission. A complexity in the data is that some submissions were further split into two or three submissions, with each having its own number of staff. Hence, we need to group the data not only by submission (i.e. unit_of_assessment_name) but also by any multiple submissions made (as specified in the *multiple_submission_name* column). We do this with fairly extensive use of GROUP BY:  
~~~~sql
SELECT ROUND(SUM(a.total)::numeric, 2) "Total FTE staff"
FROM (SELECT AVG(FTE_category_A_staff_submitted) as total
	FROM ref_table 
		GROUP BY institution_name, unit_of_assessment_name, FTE_category_A_staff_submitted, multiple_submission_name
		ORDER BY institution_name, unit_of_assessment_name) a;
~~~~
![image](https://user-images.githubusercontent.com/86210945/151543451-5385555f-8e96-43ea-9862-02de4aed20dc.png)


#### Question 3: which institutions scored the highest 4* ratings for philosophy? 

Let us write a function that accepts any unit of assessment name and returns the results for that subject: 

~~~~sql
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
		SELECT	institution_name,
			unit_of_assessment_name,
			profile,
			star_rating,
			percentage
		FROM ref_table 
		WHERE unit_of_assessment_name=uoa OR uoa is null 
			GROUP BY unit_of_assessment_name, institution_name, 
				multiple_submission_name, profile, star_rating, percentage 
			ORDER BY institution_name;
	end;
	$$;

 
SELECT 
	a.institution_name as "Institution name", 
	a.percentage as "Overall quality profile"
FROM (
	SELECT *  FROM get_table('Philosophy') 
) AS a 
WHERE a.profile='Overall' AND a.star_rating='4*' ORDER BY a.percentage DESC;

~~~~

![image](https://user-images.githubusercontent.com/86210945/151551121-ee301459-bc43-4a20-a53d-cf2cef57920f.png)

We see that the University of Oxford scores the highest. 

#### Question 4: Which institution scored highest for philosophy in terms of *both* 4* and 3*?

This time we'll use a view: 

~~~~sql
-- create view 
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
		
-- query 
SELECT 	a.institution_name as "Institution name", 
	ROUND(AVG(a.percentage),2) as "Overall quality profile"
FROM (SELECT * FROM UOA_table) AS a 
WHERE a.profile='Overall' AND (a.star_rating='4*' OR a.star_rating='3*') 
	GROUP BY a.institution_name ORDER BY "Overall quality profile" DESC;
~~~~

![image](https://user-images.githubusercontent.com/86210945/151571200-12cd3162-08e8-4bc1-bc96-15e91e3674c6.png)

#### Question 5: Give the rankings in terms of ‘research power’.

According to the University of Leeds [website](https://ref2014.leeds.ac.uk/brand-new-page/definitions/), 'research power' is derived from something called the 'grade point average (GPA)'. We first calculate the GPA with the following steps: 

for each institution, and each unit of assessment (UOA)
1. Multiply each percentage by its star rating. (E.g. if it has a value of 6.4% for 4*, we calculate 4 x 6.4 = 25.6. If it has 24% for 3* we do 3 x 24 = 72, and so on for 2* and 1*. We treat 'unclassified' as multiplying by 0.)
2. Add these values together.
3. Divide this result by 100

Now we have the GPA for each UOA. The final step is this: 

4. For each UOA, multiply the GPA by FTE for that UOA

The University of Leeds maintains that it ranks number 10 in terms of 'research power' - which will serve as a convenient sanity check for our query. To perform all this with PostgreSQL we end up with a fairly long query since we peforming a culmination of several mathematical functions. To reduce the number of subqueries here we use a view:   

~~~~sql
-- view 
CREATE OR REPLACE VIEW gpa_table AS
SELECT 	institution_name, 
	unit_of_assessment_name, 
	multiple_submission_name, 
	FTE_category_A_staff_submitted as fte,
	profile,
	ROUND(SUM(a.gpa)/100,2) as overall_gpa -- add the GPAs together and divide by 100 
FROM 	(SELECT	institution_name, 
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
SELECT 	ROW_NUMBER() OVER(ORDER BY SUM(fte*overall_gpa) DESC) "result", -- (show numbers next to results)
	institution_name, 
	ROUND((SUM(fte*overall_gpa)/SUM(fte)),2) as fte_weighted_gpa, 
	SUM(fte) as "total fte in uni",
	SUM(fte*overall_gpa) as "SUM of fte * overall_gpa",
	SUM(overall_gpa) as "overall gpa"	
FROM (SELECT * FROM gpa_table) AS a
GROUP BY institution_name
ORDER BY "SUM of fte * overall_gpa" DESC;
~~~~

University College London scores highest. We also see that Leeds is indeed number 10 on this calculation: 

![image](https://user-images.githubusercontent.com/86210945/151576700-eec8c88e-aff4-4862-baa7-e4153c9489ea.png)

#### Question 6: Which units of assessment had the highest submission counts? 

Here we use a Common Table Expression (CTE):

~~~~sql
WITH a AS (
	SELECT	unit_of_assessment_name, 
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
~~~~

![image](https://user-images.githubusercontent.com/86210945/151578087-fd8d5ce3-d587-4afd-9c0a-bac5c2a579f1.png)

## Task 4: Import new data and combine with original data

According to this [higher education blog](https://wonkhe.com/blogs/ref-2014-sector-results-2/), the submitted figures do not tell the whole story. This is because they only include the FTE staff that institutions decided to put forward. However, a 'contextual' [dataset](https://www.hesa.ac.uk/news/18-12-2014/research-excellence-framework-data) was subsequently published showing the numbers of staff that were *eligible to be put forward* per institution. Perhaps some institutions, for instance, only put forward their most impressive staff. Let us compare the staff numbers submitted with the numbers that were eligible for each institution, which wll give us an 'Intensity' of research value for each institution, which equates to *submitted FTE / eligible FTE*. In what follows we will import this new data, convert it to a .csv and store it locally. We then use SQL to join it with our existing data and calculate the intensity scores. 

#### 1. Create a table with data types appropriate to the columns in the .csv
~~~~sql
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
~~~~

#### 2. Import data (via psql)
```console
\copy raw_data_context FROM 'C:/Users/Public/SQL_test_project/raw_data_context.csv' WITH CSV HEADER;
```

#### 3. As before, we need to clean a couple of columns:
~~~~sql
UPDATE raw_data_context SET unit_of_assessment_number = REGEXP_REPLACE(unit_of_assessment_number, '[^0-9]+', '00', 'g')
ALTER TABLE raw_data_context ALTER COLUMN unit_of_assessment_number TYPE INT USING unit_of_assessment_number::integer;

UPDATE raw_data_context SET FTE_scaled = REGEXP_REPLACE(FTE_scaled, '[^0-9]+', '0', 'g')
ALTER TABLE raw_data_context ALTER COLUMN FTE_scaled TYPE INT USING FTE_scaled::integer;
~~~~

Now that we have the data we want to merge this with our existing data. Our strategy will be to create two temp tables and then join them:

~~~~sql
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
SELECT	institution_code, 
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
SELECT 	fte_submitted.institution_code,
	fte_submitted.institution_name,
	fte_submitted."Submitted FTE",  
	fte_eligible."Eligible FTE",
	ROUND(fte_submitted."Submitted FTE"/NULLIF(fte_eligible."Eligible FTE", 0),2) AS "Intensity"
FROM fte_submitted 
INNER JOIN fte_eligible 
	ON fte_submitted.institution_code = fte_eligible.ukprn
WHERE ROUND(fte_submitted."Submitted FTE"/NULLIF(fte_eligible."Eligible FTE", 0),2) <1 
	ORDER BY "Intensity" DESC;

~~~~

![image](https://user-images.githubusercontent.com/86210945/151791797-c41af54d-82b8-4911-815a-b18e5887d8aa.png)

This gives us the research intesity, which we could go on to use to weight the previous results (we won't do this in this exploration, however). All we would need to do is to multiply this intensity figure by the GPA figures we already calculated for each institution. This would give us a somewhat different ranking of research power for UK institutions. 

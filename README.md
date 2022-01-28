# REF-2014-SQL-data-exploration

This is a data exploration using the [UK University Research Excellence Framework Ratings 2014](https://public.tableau.com/s/sites/default/files/media/Resources/Research%20Excellence%20Framework%202014%20Results_Pivoted.xlsx).  Conducted by the four UK higher education funding bodies, its purpose was to assess the quality of research in UK higher education institutions. It contains data on 154 UK research institutions, each of which made submissions for up to 36 'units of assessment' (e.g. history, philosophy, biological sciences, etc.) Each submission was graded in terms of the university's output, research environment and 'impact' the research had on society in general. 

In what follows, I use PostgreSQL to import and analyse the data. I worked primarily in PgAdmin, though also use psql. A range of skills are utilised, including: creating tables, setting and converting data types, suqberying, creating user-defined functions, views, grouping data, temp tables, joins, CTEs.    

## Overview of the data

The data comes in the form of an Excel spreadsheet which we convert to a .csv. Below shows the format of the raw data. Here we have one university (Anglia Ruskin) and one of its submissions (Allied Health Professions, Dentistry, Nursing and Pharmacy). Each submission is broken into 4 categories (outputs, impact, environment and overall) and each of these in turn is given a star rating (from 4* to unclassified). The percentage column shows the degree to which that category fell under each rating. Hence, the better submissions will have more 4* and 3* for each category. To simplify things, I focus only on the 'overall' category, which is the average of the other three.   

![image](https://user-images.githubusercontent.com/86210945/151533542-42289c04-8680-408a-b959-2456d492c0f5.png)

### Task 1: create a table 
First we create a table with columns that match the .csv file columns. Two columns (institution_code and percentage) are initially set to varchar when really they should be INT and NUMERIC respectively. This is because (as it turns out) there are some non-numeric characters in those columns which cause errors when using numeric types.    

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
) 
~~~~


### Task 2: import the data
In psql, we run the following:

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

### Task 3: Data cleaning

We'll work with a duplicate of the raw_data table: 
~~~~sql
CREATE TABLE ref_table AS (SELECT * FROM raw_data);
~~~~

It turns out that some of the columns which should have numeric data types have some non-numeric characters in them. We can see this by using a bit of regex:
~~~~sql
SELECT institution_code, id FROM raw_data WHERE institution_code !~ '^([0-9]+[.]?[0-9]*|[.][0-9]+)$'; 
~~~~
![image](https://user-images.githubusercontent.com/86210945/151539222-1a480bf3-ed33-483e-97a0-eceb54b2d0e0.png)
...

We'll remove the offending characters by using REGEXP_REPLACE to replace them with a space, and then converting the spaces to NULL (for we won't be able to cast the type to a numeric with a space): 
~~~~sql
UPDATE ref_table SET institution_code = REGEXP_REPLACE(institution_code, '[^0-9]+', '', 'g')
UPDATE ref_table SET institution_code = NULLIF(institution_code, '');
ALTER TABLE ref_table ALTER COLUMN institution_code TYPE INT USING institution_code::integer;
~~~~

(We do similar for the other column, which had nonnumeric characters:)
~~~~sql
UPDATE ref_table SET percentage = REGEXP_REPLACE(percentage, '[^0-9.]+', '', 'g');
UPDATE ref_table SET percentage = NULLIF(percentage, '');
ALTER TABLE ref_table ALTER COLUMN percentage TYPE NUMERIC(4,1) USING percentage::numeric(4,1);
~~~~

### Task 4: data exploration 

We can now run queries on the data. 

Q1: which were the top 5 institutions in terms of 4* and 3*? 

~~~~sql
SELECT institution_name, ROUND(AVG(percentage),2) FROM ref_table 
	WHERE profile='Overall' AND (star_rating='4*' OR star_rating='3*') 
		GROUP BY institution_name ORDER BY AVG(percentage) DESC LIMIT 5;
~~~~
![image](https://user-images.githubusercontent.com/86210945/151540575-324011f2-6bb1-49b6-884f-e9d2c45fb81c.png)

Q2: how many FTE (full-time equivalent) staff were there in total? According to the www.ref.ac.uk website, this number should be 52,061.  

Each submission had a given number of FTE staff, and so we need to add together the staff of every submission. A complexity in the data is that some submissions were further split into two or three submissions, with each having its own number of staff. Hence, we need to group the data not only by submission (i.e. unit_of_assessment_name) but also by any multiple submissions made (multiple_submission_name). We do this with fairly extensive use of GROUP BY:  
~~~~sql
SELECT 
	ROUND(SUM(a.total)::numeric, 2) "Total FTE staff"
FROM (SELECT 
		AVG(FTE_category_A_staff_submitted) as total
	FROM ref_table 
		GROUP BY institution_name, unit_of_assessment_name, FTE_category_A_staff_submitted, multiple_submission_name
		ORDER BY institution_name, unit_of_assessment_name) a
~~~~
![image](https://user-images.githubusercontent.com/86210945/151543451-5385555f-8e96-43ea-9862-02de4aed20dc.png)


Q3: which institution scored highest for philosophy? 

Let us write a function that accepts a unit of assessment name and returns the results for that subject. (We can also make it return the rankings for all subjects by passing in null as the argument): 

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
		SELECT 
			institution_name,
			unit_of_assessment_name,
			profile,
			star_rating,
			percentage
		FROM ref_table WHERE unit_of_assessment_name=uoa OR uoa is null 
			GROUP BY unit_of_assessment_name, institution_name, 
				multiple_submission_name, profile, star_rating, percentage 
			ORDER BY institution_name;
	end;
	$$

 
SELECT 
	a.institution_name AS "Institution name", 
	a.percentage AS "Overall quality profile"
FROM (
	SELECT *  FROM get_table('Philosophy') 
) AS a 
WHERE a.profile='Overall' AND a.star_rating='4*' ORDER BY a.percentage DESC

~~~~

![image](https://user-images.githubusercontent.com/86210945/151551121-ee301459-bc43-4a20-a53d-cf2cef57920f.png)

Q4: Which institution scored highest for philosophy in terms of both 4* and 3*?

This time we'll use a view: 

~~~~sql
-- create view 
CREATE VIEW UOA_table AS
SELECT 
	institution_name, 
	unit_of_assessment_name, 
	profile, 
	star_rating, 
	percentage 
FROM ref_table WHERE unit_of_assessment_name='Philosophy'
	GROUP BY unit_of_assessment_name, institution_name, multiple_submission_name, 
		profile, star_rating, percentage ORDER BY institution_name;
-- query 
SELECT 
	a.institution_name AS "Institution name", 
	ROUND(AVG(a.percentage),2) AS "Overall quality profile"
FROM (SELECT * FROM UOA_table) AS a 
WHERE a.profile='Overall' AND (a.star_rating='4*' OR a.star_rating='3*') 
	GROUP BY a.institution_name ORDER BY "Overall quality profile" DESC
~~~~

![image](https://user-images.githubusercontent.com/86210945/151571200-12cd3162-08e8-4bc1-bc96-15e91e3674c6.png)

Q5: The University of Leeds maintains that it ranks number 10 in terms of 'research power'. According to the university [website](https://ref2014.leeds.ac.uk/brand-new-page/definitions/)  this value is derived from the 'grade point average (GPA)' x FTE. After a close look at the document in the link, we see that GPA is calculated with the following steps: for each institution, and each subject
1. Multiply each percentage by its star rating. E.g. if it has a value of 6.4% for 4*, we calculate 4 x 6.4 = 25.6. We do the same for 3*, 2* and 1*. We treat 'unclassified' as multiplying by 0. 
2. Add them all together. That is, add the results for 1*, 2*, 3*, 4* together. 
3. Divide this result by 100
Now we have the GPA for each subject (UOA). The final step is this: 
4. For each UOA, multiply the GPA by FTE for that UOA

To perform this with PostgreSQL we end up with a fairly big query, since we peforming several mathematical functions. To reduce the number of subqueries here we use a view:   

~~~~sql
-- view 
CREATE OR REPLACE VIEW gpa_table AS
SELECT 
	institution_name, 
	unit_of_assessment_name, 
	multiple_submission_name, 
	FTE_category_A_staff_submitted AS fte,
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
	FROM ref_table WHERE profile='Overall'
		GROUP BY institution_name, unit_of_assessment_name, multiple_submission_name, 
			FTE_category_A_staff_submitted, profile, star_rating, percentage
	  ) as a GROUP BY institution_name, unit_of_assessment_name, 
	  	multiple_submission_name, FTE_category_A_staff_submitted, profile;

-- query 
SELECT 
	ROW_NUMBER() OVER(ORDER BY SUM(fte*overall_gpa) DESC) "result", -- (show numbers next to results)
	institution_name, 
	ROUND((SUM(fte*overall_gpa)/SUM(fte)),2) AS fte_weighted_gpa, 
	SUM(fte) as "total fte in uni",
	SUM(fte*overall_gpa) AS "SUM of fte * overall_gpa",
	SUM(overall_gpa) AS "overall gpa"	
FROM (SELECT * FROM gpa_table) AS a
GROUP BY institution_name
ORDER BY "SUM of fte * overall_gpa" DESC
~~~~

We see that Leeds is indeed number 10 on this calculation: 

![image](https://user-images.githubusercontent.com/86210945/151576700-eec8c88e-aff4-4862-baa7-e4153c9489ea.png)

Q:  List the 36 subjects in terms of submission count, max to min.

Here we use a Common Table Expression (CTE):
~~~~sql
WITH a AS (
	SELECT 
		unit_of_assessment_name, 
		unit_of_assessment_number, 
		multiple_submission_name, 
		institution_name 
	FROM ref_table
		GROUP BY institution_name, unit_of_assessment_name, unit_of_assessment_number, 
			multiple_submission_name ORDER BY unit_of_assessment_name, institution_name
) SELECT 
	unit_of_assessment_number, 
	unit_of_assessment_name, 
	COUNT(unit_of_assessment_name) as "Number of submissions"
FROM a
	GROUP BY unit_of_assessment_name, unit_of_assessment_number 
	ORDER BY "Number of submissions" DESC
~~~~

![image](https://user-images.githubusercontent.com/86210945/151578087-fd8d5ce3-d587-4afd-9c0a-bac5c2a579f1.png)

# Import new data and combine with original data



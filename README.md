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





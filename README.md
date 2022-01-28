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

We can, if we like, add a primary key to the table: 
~~~~sql 
ALTER TABLE raw_data ADD COLUMN id SERIAL PRIMARY KEY;
~~~~

### Task 3: Data cleaning



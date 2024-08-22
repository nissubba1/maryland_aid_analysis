-- ***************Maryland Aids Database Creation and Cleaning *******************-----
-- Created by Nishan Subba

DROP DATABASE IF EXISTS maryland_aids_db;

CREATE DATABASE maryland_aids_db;

DROP TABLE IF EXISTS maryland_aids_09_23;

CREATE TABLE maryland_aids_09_23
(
    aid_transaction_id SERIAL
        PRIMARY KEY,
    grantor TEXT,
    grantee TEXT,
    zip_code TEXT,
    fiscal_year INT,
    amount NUMERIC(12, 2),
    description TEXT,
    category TEXT,
    date DATE
);

-- Check how many entries are there
SELECT
    COUNT(*)
FROM
    maryland_aids_09_23;
-- There are currently before any cleaning 19,482 records

-- ************ DATA CLEANING ********************
/*
 RULES AND GUIDELINES FOR CLEANING DATA:
 1. ALL 'Grantor' and Grantee' must be capitalized
 2. Separate 'Grantor' into two column named: 'Grantor' and 'Program'
 3. The Grantor section will include a department name and Program will include which program the aid was given for/by
 4. Standardize all non-alphanumerics such as [&, -, /]
 5. Change '&' to 'AND' for consistency
 6. Replace all dash '-' with slash '/'
 7. Standardize all spaces by removing any extra or redundant spaces
 8. Standardize abbreviation such as 'EQUIP' and 'EQUIPMENT' which will be changed to 'EQUIPMENT'
 9. Replace blank aid category with 'Unknown' since I don't it's type
 */

-- For data cleaning process, I'll be extensively using transaction to make sure no data is updated or changed accidentally. I'll will be also using savepoint. All the data cleaning will be completed with postgresql.

-- Change the capitalization of all grantor and grantee
BEGIN TRANSACTION;

UPDATE maryland_aids_09_23
SET
    grantor = UPPER(grantor),
    grantee = UPPER(grantee);

SAVEPOINT update_capitalization;

-- Change Hyphen ' - ' with a slash '/'
UPDATE maryland_aids_09_23
SET
    grantor = REGEXP_REPLACE(grantor, ' - ', '/', 1);

SAVEPOINT replace_hyphen;

-- Trim all spaces, tabs, and new line
UPDATE maryland_aids_09_23
SET
    grantor = REGEXP_REPLACE(TRIM(grantor), '  ', ' ', 'g')
WHERE
    grantor IS NOT NULL;

UPDATE maryland_aids_09_23
SET
    grantor = 'Maryland Department of Planning/Historic Preservation Grant Program'
WHERE
    grantor =
    'Maryland Department of Planning/Maryland Department of Planning/Heritage Areas Authority                  &                                Maryland Department of Planning - Historic Preservation Grant Program';

SAVEPOINT trim_spaces;

COMMIT;

-- Create a two new column Department and Program
ALTER TABLE maryland_aids_09_23
    ADD COLUMN department TEXT;
ALTER TABLE maryland_aids_09_23
    ADD COLUMN program TEXT;

BEGIN TRANSACTION;

-- Split the department and program name
UPDATE maryland_aids_09_23
SET
    department = SPLIT_PART(grantor, '/', 1),
    program = CASE
                  WHEN POSITION('/' IN grantor) > 0 THEN SPLIT_PART(grantor, '/', 2)
              END;

-- Change the capitalization of Department and Program
UPDATE maryland_aids_09_23
SET
    department = UPPER(department),
    program = UPPER(program);

-- Ok everything is working
COMMIT;

-- There are some inconsistency in the category column
SELECT
    category
FROM
    maryland_aids_09_23
GROUP BY
    category;

-- The current categories are: L, Grant, NULL, Loan, and Contract
-- However, I want to change L to Loan and replace null with unknown
BEGIN TRANSACTION;

UPDATE maryland_aids_09_23
SET
    category = 'Loan'
WHERE
    category = 'L';

UPDATE maryland_aids_09_23
SET
    category = 'Unknown'
WHERE
    category IS NULL;

-- Fix the inconsistent appreciation
SELECT
    program
FROM
    maryland_aids_09_23
WHERE
     program LIKE '%EQUIP%'
  OR program LIKE '%EQUIPMENT%'
GROUP BY
    program;


BEGIN TRANSACTION;

UPDATE maryland_aids_09_23
SET
    program = REPLACE(program, 'EQUIPMENTMENT', 'EQUIPMENT');

ROLLBACK;

SELECT
    department,
    program
FROM
    maryland_aids_09_23
WHERE
    program IS NULL
GROUP BY
    department, program;

-- There are lot of instances where department and program are switched or program is null
-- I'll go through each record to fix the department and program
UPDATE maryland_aids_09_23
SET
    program = 'MARYLAND HIGHWAY SAFETY',
    department = UPPER('Department of Transportation')
WHERE
    department = 'MARYLAND HIGHWAY SAFETY';

UPDATE maryland_aids_09_23
SET
    program = '',
    department = ''
WHERE
    department = '';


SELECT
    department
FROM
    maryland_aids_09_23
WHERE
    department = 'DEPARTMENT OF TRANSPORTATION';

-- There are currently 149 records that need to be updated, and doing each update using update statement is going to take too long, so I'll be using pl/pgsql

-- Create a function that does this:
/*
 1. Takes current department name
 2. Update the program column and replace it with the department name
 3. Update the department with appropriate name
 */

CREATE OR REPLACE FUNCTION change_dept_program(curr_dept_name TEXT, new_dept_name TEXT)
    RETURNS TEXT
    LANGUAGE plpgsql
AS
$$
BEGIN
    UPDATE maryland_aids_09_23
    SET
        program = curr_dept_name,
        department = UPPER(new_dept_name)
    WHERE
        department = curr_dept_name;

    IF found THEN
        RETURN 'Update successful.';
    ELSE
        RETURN 'No records updated.';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'Error occurred: ' || sqlerrm;
END;
$$;

-- Testing function
-- OFFICE OF GRANTS MANAGEMENT
SELECT
    department,
    program
FROM
    maryland_aids_09_23
WHERE
    department = UPPER('Department of Budget and Management');

BEGIN TRANSACTION;

-- Call the function
SELECT change_dept_program('OFFICE OF GRANTS MANAGEMENT', 'Department of Budget and Management');

-- Function successfully updated the record
-- Will do the rest of the records

SELECT
    change_dept_program('ADULT EDUCATION AND FAMILY LITERACY ACT (AEFLA)', 'Maryland State Department of Education');
SELECT change_dept_program('MARKETING SPAY AND NEUTER PROGRAM', 'Maryland Department of Agriculture');
SELECT change_dept_program('LAWTON CONSERVATION LOAN PROGRAM', 'Maryland Energy Administration');
SELECT change_dept_program('STATEWIDE PROGRAMS OPERATIONS', 'Maryland Higher Education Commission');
SELECT change_dept_program('FAMILY INVESTMENT ADMINISTRATION', 'Maryland Department of Human Services');
SELECT change_dept_program('OFFICE OF THE SECRETARY, DEPUTY SECRETARY FOR OPERATIONS', 'Maryland Department of Labor');
SELECT
    change_dept_program('COMMERCIAL AND INDUSTRIAL (C&I) DEEP ENERGY RETROFIT PROGRAM',
                        'Maryland Energy Administration');
SELECT change_dept_program('OFFICE OF CYBER DEVELOPMENT AND AEROSPACE', 'Maryland Department of Commerce');
SELECT change_dept_program('PHOTOVOLTAIC (PV) IN PARKING LOTS GRANTS PROGRAM', 'Maryland Energy Administration');
SELECT
    change_dept_program('CHESAPEAKE & ATLANTIC COASTAL BAYS TRUST FUND', 'MARYLAND Department of Natural Resources');

-- Step 2

SELECT change_dept_program('RENT ALLOWANCE', 'Maryland Department of Housing and Community Development');
SELECT change_dept_program('RESOURCE CONSERVATION GRANTS', 'Maryland Department of Agriculture');
SELECT
    change_dept_program('MARYLAND VEHICLE THEFT PREVENTION COUNCIL SPATIAL ANALYSIS & ON-DEMAND SUPPORT',
                        'Maryland State Police');
SELECT change_dept_program('HEAD START', 'Maryland State Department of Education');
SELECT change_dept_program('OFFICE OF BUSINESS DEVELOPMENT', 'Maryland Department of Commerce');
SELECT change_dept_program('MARKETING SERVICES', 'Maryland Department of Commerce');
SELECT change_dept_program('RENTAL HOUSING', 'Maryland Department of Housing and Community Development');
SELECT
    change_dept_program('NATURALLY OCCURRING RETIREMENT COMMUNITIES (NORC) (MONT. HOLOCAUST SURVIVORS)',
                        'Maryland Department of Aging');
SELECT change_dept_program('PARTNERSHIP FOR WORKFORCE QUALITY', 'Maryland Department of Commerce');
SELECT change_dept_program('OFFICE OF HOME ENERGY PROGRAMS', 'Maryland Department of Human Services');

SELECT
    change_dept_program('GOVERNOR''S OFFICE OF COMMUNITY INITIATIVES',
                        'The Governor’s Office of Community Initiatives');
SELECT change_dept_program('MISCELLANEOUS GRANTS TO PRIVATE NON-PROFIT GROUPS', 'Governor’s Grants Office');
SELECT change_dept_program('REVITALIZATION STRATEGY', 'Maryland Department of Housing and Community Development');
SELECT change_dept_program('ACCESS TO JUSTICE', 'Justice');
SELECT change_dept_program('AIRPORT FACILITIES AND CAPITAL EQUIPMENT', 'Maryland Department of Transportation');
SELECT change_dept_program('SENIOR CARE', 'Maryland Department of Aging');
SELECT
    change_dept_program('EMERGENCY SOLUTIONS GRANTS (ESG)', 'Maryland Department of Housing and Community Development');
SELECT change_dept_program('COLLEGE PREPARATION INTERVENTION PROGRAM (CPIP)', 'Maryland Higher Education Commission');
SELECT change_dept_program('MD STATE ARTS COUNCIL', 'Department of Commerce');
SELECT change_dept_program('ANIMAL HEALTH', 'MARYLAND Department of Agriculture');

SELECT change_dept_program('FOREST SERVICE', 'MARYLAND DEPARTMENT OF NATURAL RESOURCES');
SELECT change_dept_program('LEAD HAZARD', 'MARYLAND Department of the Environment');
SELECT change_dept_program('VULNERABLE ELDERLY PROGRAMS INITIATIVE (VEIP)', 'MARYLAND DEPARTMENT OF TRANSPORTATION');
SELECT change_dept_program('SUPPORT TO MAINTAINING ACTIVE CITIZENS (MAC)', 'Maryland Department of Aging');
SELECT change_dept_program('LOW AND MODERATE INCOME (LMI) COMMUNITY GRANTS', 'Maryland Energy Administration');
SELECT change_dept_program('MEDIATION & CONFLICT RESOLUTION OFFICE', 'Justice');
SELECT change_dept_program('MD SMALL BUSINESS DEVELOPMENT FINANCING AUTHORITY', 'Maryland Department of Commerce');
SELECT change_dept_program('COMMUNITY SOLAR', 'Maryland Energy Administration');
SELECT
    change_dept_program('ELECTRIC VEHICLE SUPPLY EQUIPMENT (EVSE) REBATE PROGRAM', 'Maryland Energy Administration');
SELECT change_dept_program('GOVERNOR''S WORKFORCE DEVELOPMENT BOARD', 'Governor''s Workforce Investment Board');

SELECT
    department,
    program
FROM
    maryland_aids_09_23
WHERE
    program IS NULL
GROUP BY
    department, program;
SELECT
    COUNT(*)
FROM
    maryland_aids_09_23
WHERE
    program IS NULL;

SELECT change_dept_program('OFFICE OF GRANTS MANAGEMENT', 'Department of Budget and Management');
SELECT
    change_dept_program('ADULT EDUCATION AND FAMILY LITERACY ACT (AEFLA)', 'Maryland State Department of Education');
SELECT
    change_dept_program('MARKETING SPAY AND NEUTER PROGRAM', '
Maryland Department of Agriculture');
SELECT change_dept_program('LAWTON CONSERVATION LOAN PROGRAM', 'Maryland Energy Administration');
SELECT change_dept_program('STATEWIDE PROGRAMS OPERATIONS', 'Maryland State Department of Education');
SELECT change_dept_program('FAMILY INVESTMENT ADMINISTRATION', 'Maryland Department of Human Services');
SELECT change_dept_program('OFFICE OF THE SECRETARY, DEPUTY SECRETARY FOR OPERATIONS', 'Maryland Department of Labor');
SELECT
    change_dept_program('COMMERCIAL AND INDUSTRIAL (C&I) DEEP ENERGY RETROFIT PROGRAM',
                        'Maryland Energy Administration');
SELECT change_dept_program('OFFICE OF CYBER DEVELOPMENT AND AEROSPACE', 'Maryland Department of Commerce');
SELECT change_dept_program('PHOTOVOLTAIC (PV) IN PARKING LOTS GRANTS PROGRAM', 'Maryland Energy Administration');

-- SELECT grantor, TO_CHAR(SUM(amount), '$FM999,999,999,999.00') AS total_amount

-- Making records consistency
SELECT
    department
FROM
    maryland_aids_09_23
WHERE
    maryland_aids_09_23.department LIKE '%TRANSPORTATION%'
GROUP BY
    department;

BEGIN TRANSACTION;

UPDATE maryland_aids_09_23
SET
    department = 'DEPARTMENT OF TRANSPORTATION'
WHERE
    department IN ('DEPARTMENT OF TRANSPORTATION', 'MARYLAND DEPARTMENT OF TRANSPORTATION');

ROLLBACK;

COMMIT;

BEGIN TRANSACTION;
UPDATE maryland_aids_09_23
SET
    grantee = 'WASHINGTON METROPOLITAN AREA TRANSIT AUTHORITY'
WHERE
    grantee IN ('WASHINGTON METROPOLITAN AREA TRANSIT AUTHORITY', 'WMATA',
                'WASHINGTON METROPOLITAN AREA TRANSIT AUTHORITY (WMATA)');

UPDATE maryland_aids_09_23
SET
    grantee = 'WASHINGTON SUBURBAN TRANSIT'
WHERE
    grantee IN ('WASHINGTON SUBURBAN TRANSIT', 'WASHINGTON SUBURBAN-TRANSIT C TOTAL', 'WASHINGTON SUBURBAN-TRANSIT C');

COMMIT;

UPDATE maryland_aids_09_23
SET
    department = 'MARYLAND DEPARTMENT OF EDUCATION'
WHERE
    department IN
    ('MARYLAND DEPARTMENT OF EDUCATION', 'MARYLAND STATE DEPARTMENT OF EDUCATION', 'STATE DEPARTMENT OF EDUCATION');

-- Once those records are adjusted, we end up with this result:
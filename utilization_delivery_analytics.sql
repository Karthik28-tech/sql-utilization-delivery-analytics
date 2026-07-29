-- ============================================================
-- Employee Utilization & Project Delivery Analytics
-- Advanced SQL Portfolio Project
-- Author: Raparthi Karthik
-- ============================================================

-- ============================================================
-- SECTION 1: SCHEMA CREATION
-- ============================================================

CREATE DATABASE utilization_delivery_db;
USE utilization_delivery_db;

CREATE TABLE employees (
    employee_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    role VARCHAR(50),
    department VARCHAR(50),
    hourly_rate DECIMAL(8,2),
    join_date DATE
);

CREATE TABLE clients (
    client_id INT PRIMARY KEY AUTO_INCREMENT,
    client_name VARCHAR(100) NOT NULL,
    industry VARCHAR(50),
    region VARCHAR(50)
);

CREATE TABLE projects (
    project_id INT PRIMARY KEY AUTO_INCREMENT,
    client_id INT,
    project_name VARCHAR(100) NOT NULL,
    start_date DATE,
    end_date DATE,
    budget DECIMAL(12,2),
    status VARCHAR(20),
    FOREIGN KEY (client_id) REFERENCES clients(client_id)
);

CREATE TABLE timesheets (
    timesheet_id INT PRIMARY KEY AUTO_INCREMENT,
    employee_id INT,
    project_id INT,
    work_date DATE,
    hours_logged DECIMAL(4,2),
    billable CHAR(1),
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
    FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

-- ============================================================
-- SECTION 2: SAMPLE DATA
-- (employees, clients, projects inserted here manually —
--  see employees_clients_projects_insert.sql;
--  timesheets loaded separately via timesheets_insert.sql, ~1177 rows)
-- ============================================================

-- ============================================================
-- SECTION 3: ADVANCED QUERY 1 — Conditional Aggregation
-- Monthly utilization % per employee (billable hours / total hours)
-- ============================================================

SELECT
    e.employee_id,
    e.name,
    e.department,
    MONTH(t.work_date) AS month,
    SUM(CASE WHEN t.billable = 'Y' THEN t.hours_logged ELSE 0 END) AS billable_hours,
    SUM(t.hours_logged) AS total_hours,
    ROUND(SUM(CASE WHEN t.billable = 'Y' THEN t.hours_logged ELSE 0 END) / SUM(t.hours_logged) * 100, 1) AS utilization_pct
FROM timesheets t
JOIN employees e ON t.employee_id = e.employee_id
GROUP BY e.employee_id, e.name, e.department, MONTH(t.work_date)
ORDER BY e.employee_id, month;

-- ============================================================
-- SECTION 4: ADVANCED QUERY 2 — CTE + Window Function
-- Rank employees by utilization within their department, per month
-- ============================================================

WITH monthly_utilization AS (
    SELECT
        e.employee_id,
        e.name,
        e.department,
        MONTH(t.work_date) AS month,
        ROUND(SUM(CASE WHEN t.billable = 'Y' THEN t.hours_logged ELSE 0 END) / SUM(t.hours_logged) * 100, 1) AS utilization_pct
    FROM timesheets t
    JOIN employees e ON t.employee_id = e.employee_id
    GROUP BY e.employee_id, e.name, e.department, MONTH(t.work_date)
)
SELECT
    *,
    RANK() OVER (PARTITION BY department, month ORDER BY utilization_pct DESC) AS dept_rank
FROM monthly_utilization
ORDER BY month, department, dept_rank;

-- ============================================================
-- SECTION 5: ADVANCED QUERY 3 — Window Function (LAG)
-- Month-over-month utilization change per employee
-- ============================================================

WITH monthly_utilization AS (
    SELECT
        e.employee_id,
        e.name,
        e.department,
        MONTH(t.work_date) AS month,
        ROUND(SUM(CASE WHEN t.billable = 'Y' THEN t.hours_logged ELSE 0 END) / SUM(t.hours_logged) * 100, 1) AS utilization_pct
    FROM timesheets t
    JOIN employees e ON t.employee_id = e.employee_id
    GROUP BY e.employee_id, e.name, e.department, MONTH(t.work_date)
)
SELECT
    *,
    LAG(utilization_pct) OVER (PARTITION BY employee_id ORDER BY month) AS prev_month_utilization,
    ROUND(utilization_pct - LAG(utilization_pct) OVER (PARTITION BY employee_id ORDER BY month), 1) AS change_vs_prev_month
FROM monthly_utilization
ORDER BY employee_id, month;

-- ============================================================
-- SECTION 6: ADVANCED QUERY 4 — Correlated Subquery
-- Employees whose monthly billable hours fall below their own historical average
-- ============================================================

SELECT
    e.employee_id,
    e.name,
    MONTH(t.work_date) AS month,
    SUM(CASE WHEN t.billable = 'Y' THEN t.hours_logged ELSE 0 END) AS billable_hours
FROM timesheets t
JOIN employees e ON t.employee_id = e.employee_id
GROUP BY e.employee_id, e.name, MONTH(t.work_date)
HAVING SUM(CASE WHEN t.billable = 'Y' THEN t.hours_logged ELSE 0 END) < (
    SELECT AVG(monthly_billable)
    FROM (
        SELECT SUM(CASE WHEN t2.billable = 'Y' THEN t2.hours_logged ELSE 0 END) AS monthly_billable
        FROM timesheets t2
        WHERE t2.employee_id = e.employee_id
        GROUP BY MONTH(t2.work_date)
    ) AS emp_monthly
)
ORDER BY e.employee_id, month;

-- ============================================================
-- SECTION 7: ADVANCED QUERY 5 — Standalone Pivot via Conditional Aggregation
-- Billable vs non-billable hours per employee, as separate columns
-- (MySQL has no native PIVOT keyword — this is the standard workaround)
-- ============================================================

SELECT
    e.employee_id,
    e.name,
    SUM(CASE WHEN t.billable = 'Y' THEN t.hours_logged ELSE 0 END) AS billable_hours,
    SUM(CASE WHEN t.billable = 'N' THEN t.hours_logged ELSE 0 END) AS non_billable_hours,
    SUM(t.hours_logged) AS total_hours
FROM timesheets t
JOIN employees e ON t.employee_id = e.employee_id
GROUP BY e.employee_id, e.name
ORDER BY e.employee_id;

-- ============================================================
-- SECTION 8: VIEW — Project Margin
-- Reusable view joining projects, clients, timesheets, employees
-- to compute cost vs budget per project
-- ============================================================

CREATE VIEW v_project_margin AS
SELECT
    p.project_id,
    p.project_name,
    c.client_name,
    p.budget,
    SUM(t.hours_logged * e.hourly_rate) AS total_cost,
    p.budget - SUM(t.hours_logged * e.hourly_rate) AS remaining_budget,
    ROUND(SUM(t.hours_logged * e.hourly_rate) / p.budget * 100, 1) AS pct_budget_used
FROM projects p
JOIN clients c ON p.client_id = c.client_id
JOIN timesheets t ON p.project_id = t.project_id
JOIN employees e ON t.employee_id = e.employee_id
GROUP BY p.project_id, p.project_name, c.client_name, p.budget;

-- usage:
-- SELECT * FROM v_project_margin ORDER BY pct_budget_used DESC;

-- ============================================================
-- SECTION 9: STORED PROCEDURE — Parameterized Low Utilization Report
-- ============================================================

DELIMITER $$

CREATE PROCEDURE GetLowUtilizationEmployees(IN threshold_pct DECIMAL(5,2))
BEGIN
    SELECT
        e.employee_id,
        e.name,
        e.department,
        MONTH(t.work_date) AS month,
        ROUND(SUM(CASE WHEN t.billable = 'Y' THEN t.hours_logged ELSE 0 END) / SUM(t.hours_logged) * 100, 1) AS utilization_pct
    FROM timesheets t
    JOIN employees e ON t.employee_id = e.employee_id
    GROUP BY e.employee_id, e.name, e.department, MONTH(t.work_date)
    HAVING utilization_pct < threshold_pct
    ORDER BY month, utilization_pct;
END$$

DELIMITER ;

-- usage:
-- CALL GetLowUtilizationEmployees(60.00);

-- ============================================================
-- SECTION 10: TRIGGER — Project Status Change Audit Log
-- ============================================================

CREATE TABLE audit_log (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    project_id INT,
    old_status VARCHAR(20),
    new_status VARCHAR(20),
    changed_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$

CREATE TRIGGER trg_project_status_change
AFTER UPDATE ON projects
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO audit_log (project_id, old_status, new_status)
        VALUES (OLD.project_id, OLD.status, NEW.status);
    END IF;
END$$

DELIMITER ;

-- test:
-- UPDATE projects SET status = 'On Hold' WHERE project_id = 1;
-- SELECT * FROM audit_log;

-- ============================================================
-- SECTION 11: TRANSACTIONS — COMMIT / ROLLBACK demonstration
-- ============================================================

-- Rollback example (change is undone):
-- START TRANSACTION;
-- UPDATE timesheets SET hours_logged = 8.00 WHERE timesheet_id = 1;
-- UPDATE timesheets SET hours_logged = 8.00 WHERE timesheet_id = 2;
-- ROLLBACK;
-- SELECT hours_logged FROM timesheets WHERE timesheet_id IN (1, 2);

-- Commit example (change is permanent):
-- START TRANSACTION;
-- UPDATE timesheets SET hours_logged = 7.00 WHERE timesheet_id = 1;
-- COMMIT;
-- SELECT hours_logged FROM timesheets WHERE timesheet_id = 1;

-- ============================================================
-- SECTION 12: INDEXING + EXPLAIN
-- Demonstrating query performance improvement from indexing
-- ============================================================

-- Before index (full table scan, ~1177 rows examined):
-- EXPLAIN SELECT * FROM timesheets WHERE work_date = '2026-03-02';

CREATE INDEX idx_timesheets_workdate ON timesheets(work_date);

-- After index (ref lookup, ~13 rows examined):
-- EXPLAIN SELECT * FROM timesheets WHERE work_date = '2026-03-02';

-- Note: timesheets.employee_id and timesheets.project_id already have
-- automatic indexes created by InnoDB to enforce their FOREIGN KEY constraints,
-- so an explicit index on employee_id showed no change in EXPLAIN output —
-- this is expected, not an error.

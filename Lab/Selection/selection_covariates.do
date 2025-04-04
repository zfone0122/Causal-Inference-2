* selection_covariates.do -- Selection on observables and conditional parallel trends

clear all
capture log close
set seed 12345

********************************************************************************
* Define dgp
********************************************************************************
cap program drop dgp
program define dgp

  * 1,000 workers (25 per state), 40 states, 4 groups (250 per group), 6 years
  * First create the states
  quietly set obs 40
  gen state = _n

  * Generate 1000 workers. These are in each state. So 25 per state.
  quietly expand 25
  bysort state: gen worker=runiform(0,5)
  label variable worker "Unique worker fixed effect per state"
  quietly egen id = group(state worker)

  * Generate Covariates (Baseline values)
  gen age = rnormal(35, 10)
  gen gpa = rnormal(2.0, 0.5)

  * Center Covariates (Baseline)
  sum age, meanonly
  qui replace age = age - r(mean)
  sum gpa, meanonly
  qui replace gpa = gpa - r(mean)

  * Generate Polynomial and Interaction Terms (Baseline)
  gen age_sq = age^2
  gen gpa_sq = gpa^2
  gen interaction = age * gpa
  
  * Treatment probability increases with age and decrease with gpa
  gen propensity = 0.3 + 0.3 * (age > 0) + 0.2 * (gpa > 0)
  gen treat = runiform() < propensity

  * Generate the years
  quietly expand 6
  sort state
  bysort state worker: gen year = _n
  * years 1987 -- 1992
  replace year = 1986 + year
  
  * Post-treatment
  gen post = 0  
  qui replace post = 1 if year >= 1991

  * Generate treatment dates
  gen treat_date = 0
  replace treat_date = 1991 if treat==1

  * Generate fixed effect with control group making 10,000 more at baseline
  qui gen unit_fe = 40000 + 10000 * (treat == 0) 
  
  * Generate Potential Outcomes with Baseline and Year Difference
  gen e = rnormal(0, 1500)
  qui gen     y0 = unit_fe        + 100 * age + 1000 * gpa + e if year == 1987
  qui replace y0 = unit_fe + 1000 + 150 * age + 1500 * gpa + e if year == 1988
  qui replace y0 = unit_fe + 2000 + 200 * age + 2000 * gpa + e if year == 1989
  qui replace y0 = unit_fe + 3000 + 250 * age + 2500 * gpa + e if year == 1990
  qui replace y0 = unit_fe + 4000 + 300 * age + 3000 * gpa + e if year == 1991
  qui replace y0 = unit_fe + 5000 + 350 * age + 3500 * gpa + e if year == 1992

  * Covariate-based treatment effect heterogeneity
  gen y1 = y0
  replace y1 = y0 + 1000 + 250 * age + 1000 * gpa if year >= 1991

  * Treatment effect
  gen delta = y1 - y0
  label var delta "Treatment effect for unit i (unobservable in the real world)"
  
  * Generate observed outcome based on treatment assignment
  gen earnings = y0
  qui replace earnings = y1 if treat == 1 & year >= 1991
end

********************************************************************************
* Generate a sample
********************************************************************************
clear
quietly dgp

* Regression breaks
reg earnings treat##ib1990.year age gpa age_sq gpa_sq interaction, robust

* CSDID works
csdid earnings age gpa age_sq gpa_sq interaction, ivar(id) time(year) gvar(treat_date)
csdid_plot, group(1991)


********************************************************************************
* Monte-carlo simulation
********************************************************************************
cap program drop simulation
program define simulation, rclass
    clear 
	  quietly dgp
    
    // True ATT
    gen true_att = y1 - y0
    qui sum true_att if treat == 1 & year == 1991
    return scalar att_1991 = r(mean)
    qui sum true_att if treat == 1 & year == 1992
    return scalar att_1992 = r(mean)

    // CSDID
    qui csdid earnings age gpa age_sq gpa_sq interaction, ivar(id) time(year) gvar(treat_date)
    matrix b = e(b)
    return scalar cs_pre1987 = b[1,1]
    return scalar cs_pre1988 = b[1,2]
    return scalar cs_pre1989 = b[1,3]
    return scalar cs_post1991 = b[1,4]
    return scalar cs_post1992 = b[1,5]
    return scalar cs_att = (b[1,4] + b[1,5]) / 2
    
    // OLS
    qui reg earnings treat##ib1990.year age gpa age_sq gpa_sq interaction, robust
    return scalar ols_pre1987 = _b[1.treat#1987.year]
    return scalar ols_pre1988 = _b[1.treat#1988.year]
    return scalar ols_pre1989 = _b[1.treat#1989.year]
    return scalar ols_post1991 = _b[1.treat#1991.year]
    return scalar ols_post1992 = _b[1.treat#1992.year]
    
    // OLS overall ATT
    qui reg earnings post##treat age gpa age_sq gpa_sq interaction, robust
    return scalar ols_att = _b[1.post#1.treat]  
end

simulate att_1991 = r(att_1991) ///
         att_1992 = r(att_1992) ///
         cs_pre1987 = r(cs_pre1987) ///
         cs_pre1988 = r(cs_pre1988) ///
         cs_pre1989 = r(cs_pre1989) ///
         cs_post1991 = r(cs_post1991) ///
         cs_post1992 = r(cs_post1992) ///
         cs_att = r(cs_att) ///
         ols_pre1987 = r(ols_pre1987) ///
         ols_pre1988 = r(ols_pre1988) ///
         ols_pre1989 = r(ols_pre1989) ///
         ols_post1991 = r(ols_post1991) ///
         ols_post1992 = r(ols_post1992) ///
         ols_att = r(ols_att), ///
         reps(100) seed(12345): simulation


// Summarize results
sum

// Store results
tempfile dataset
save ./selection_covariates.dta, replace





********************************************************************************
* Plot results
********************************************************************************

use ./selection_covariates.dta, clear

* Calculate means and standard deviations for OLS variables
summarize ols_pre1987
local ols_pre1987_mean = r(mean)
local ols_pre1987_sd = r(sd)

summarize ols_pre1988
local ols_pre1988_mean = r(mean)
local ols_pre1988_sd = r(sd)

summarize ols_pre1989
local ols_pre1989_mean = r(mean)
local ols_pre1989_sd = r(sd)

summarize ols_post1991
local ols_post1991_mean = r(mean)
local ols_post1991_sd = r(sd)

summarize ols_post1992
local ols_post1992_mean = r(mean)
local ols_post1992_sd = r(sd)

* Calculate means and standard deviations for CSDID variables
summarize cs_pre1987
local cs_pre1987_mean = r(mean)
local cs_pre1987_sd = r(sd)

summarize cs_pre1988
local cs_pre1988_mean = r(mean)
local cs_pre1988_sd = r(sd)

summarize cs_pre1989
local cs_pre1989_mean = r(mean)
local cs_pre1989_sd = r(sd)

summarize cs_post1991
local cs_post1991_mean = r(mean)
local cs_post1991_sd = r(sd)

summarize cs_post1992
local cs_post1992_mean = r(mean)
local cs_post1992_sd = r(sd)

summarize att_1992
local true_att_1991 = r(mean)
summarize att_1991
local true_att_1992 = r(mean)


* Create a new dataset for plotting
clear
set obs 5

* Define the years
gen year = 1987 + _n - 1
replace year = 1991 if _n == 4
replace year = 1992 if _n == 5

* True ATT values
gen truth = 0
replace truth = `true_att_1991' if year == 1991
replace truth = `true_att_1992' if year == 1992

* OLS means and confidence intervals
gen ols_mean = .
gen ols_ci_lower = .
gen ols_ci_upper = .
replace ols_mean = `ols_pre1987_mean' in 1
replace ols_mean = `ols_pre1988_mean' in 2
replace ols_mean = `ols_pre1989_mean' in 3
replace ols_mean = `ols_post1991_mean' in 4
replace ols_mean = `ols_post1992_mean' in 5

replace ols_ci_lower = ols_mean - 1.96 * `ols_pre1987_sd' in 1
replace ols_ci_lower = ols_mean - 1.96 * `ols_pre1988_sd' in 2
replace ols_ci_lower = ols_mean - 1.96 * `ols_pre1989_sd' in 3
replace ols_ci_lower = ols_mean - 1.96 * `ols_post1991_sd' in 4
replace ols_ci_lower = ols_mean - 1.96 * `ols_post1992_sd' in 5

replace ols_ci_upper = ols_mean + 1.96 * `ols_pre1987_sd' in 1
replace ols_ci_upper = ols_mean + 1.96 * `ols_pre1988_sd' in 2
replace ols_ci_upper = ols_mean + 1.96 * `ols_pre1989_sd' in 3
replace ols_ci_upper = ols_mean + 1.96 * `ols_post1991_sd' in 4
replace ols_ci_upper = ols_mean + 1.96 * `ols_post1992_sd' in 5

* CSDID means and confidence intervals
gen csdid_mean = .
gen csdid_ci_lower = .
gen csdid_ci_upper = .
replace csdid_mean = `cs_pre1987_mean' in 1
replace csdid_mean = `cs_pre1988_mean' in 2
replace csdid_mean = `cs_pre1989_mean' in 3
replace csdid_mean = `cs_post1991_mean' in 4
replace csdid_mean = `cs_post1992_mean' in 5

replace csdid_ci_lower = csdid_mean - 1.96 * `cs_pre1987_sd' in 1
replace csdid_ci_lower = csdid_mean - 1.96 * `cs_pre1988_sd' in 2
replace csdid_ci_lower = csdid_mean - 1.96 * `cs_pre1989_sd' in 3
replace csdid_ci_lower = csdid_mean - 1.96 * `cs_post1991_sd' in 4
replace csdid_ci_lower = csdid_mean - 1.96 * `cs_post1992_sd' in 5

replace csdid_ci_upper = csdid_mean + 1.96 * `cs_pre1987_sd' in 1
replace csdid_ci_upper = csdid_mean + 1.96 * `cs_pre1988_sd' in 2
replace csdid_ci_upper = csdid_mean + 1.96 * `cs_pre1989_sd' in 3
replace csdid_ci_upper = csdid_mean + 1.96 * `cs_post1991_sd' in 4
replace csdid_ci_upper = csdid_mean + 1.96 * `cs_post1992_sd' in 5

twoway (scatter truth year, mcolor(maroon) msize(6-pt) msymbol(lgx) mlabcolor() mfcolor(cranberry) mlwidth(medthick)) ///
       (scatter ols_mean year, mcolor(navy) msize(6-pt)) ///
       (line ols_mean year, lcolor(blue) lwidth(medthick)) ///
       (rcap ols_ci_lower ols_ci_upper year, lcolor(blue) lpattern(dash)), ///
       title("OLS vs Truth Event Study") ///
       subtitle("Additive controls specification") ///
       note("DGP uses conditional parallel trends and all controls included. 1000 Monte Carlo simulations.") ///
       legend(order(1 "Truth" 2 "OLS")) ///
	   xline(1990.5, lpattern(dash) lcolor(gray))


graph export "./selection_ols.png", as(png) name("Graph")	   replace
	   
twoway (scatter truth year, mcolor(maroon) msize(6-pt) msymbol(lgx) mlabcolor() mfcolor(cranberry) mlwidth(medthick)) ///
       (scatter csdid_mean year, mcolor(saddle) msize(6-pt)) ///
       (line csdid_mean year, lcolor(brown) lwidth(medthick)) ///
       (rcap csdid_ci_lower csdid_ci_upper year, lcolor(brown) lpattern(dash)), ///
       title("CS vs Truth Event Study") ///
       subtitle("Doubly Robust specification") ///
       note("DGP uses conditional parallel trends and all controls included. Estimated with csdid." "1000 Monte Carlo simulations.") ///
       legend(order(1 "Truth" 2 "CS")) ///
	   xline(1990.5, lpattern(dash) lcolor(gray))
	   
graph export "./selection_cs.png", as(png) name("Graph")	   replace

* Shift years slightly to avoid overlap
gen year_ols = year - 0.1
gen year_csdid = year

* Plotting
twoway (scatter truth year, mcolor(maroon) msize(6-pt) msymbol(lgx) mlabcolor() mfcolor(cranberry) mlwidth(medthick)) ///
       (scatter ols_mean year_ols, mcolor(navy) msize(6-pt)) ///
       (line ols_mean year_ols, lcolor(blue) lwidth(medthick)) ///
       (rcap ols_ci_lower ols_ci_upper year_ols, lcolor(blue)) ///
       (scatter csdid_mean year_csdid, mcolor(saddle) msize(6-pt)) ///
       (line csdid_mean year_csdid, lcolor(brown) lwidth(medthick) lpattern(dash)) ///
       (rcap csdid_ci_lower csdid_ci_upper year_csdid, lcolor(brown) lpattern(dash)), ///
       title("Event Study: OLS, CSDID, and Truth") ///
       note("DGP uses conditional parallel trends. OLS includes additive controls; CS uses double robust." "No differential timing. 1000 Monte Carlo simulations.") ///
       legend(order(1 "Truth" 3 "OLS" 6 "CS") ///
              label(1 "Truth" ) ///
              label(2 "OLS" ) ///
              label(3 "CS" )) ///
       xline(1990.5, lpattern(dash) lcolor(gray))

* Export the graph
graph export "./selection_combined.png", as(png) name("Graph") replace

* selection_fe.do - Heterogeneous trends in Y0 and selection on fixed effects
clear all
set seed 2

* First create 5 states
quietly set obs 5
gen state = _n

* Generate 250 workers in each state
expand 250
bysort state: gen unit_fe = runiform(1, 1000)
label variable unit_fe "Unique worker fixed effect per state"
egen id = group(state unit_fe)

* Generate group variable for different trends
gen group = mod(_n, 40) + 1

* Generate worker characteristics
* Age: skewed distribution with average age 35
gen age = round(rbeta(2, 5) * 65)

* Sex: balanced ratio
gen male = runiform() > 0.5

* Generate potential outcomes for the first year (1987)
gen y0_1987 = unit_fe + rnormal(0, 10)

* Generate potential outcomes for subsequent years with more stochastic elements
gen trend = 5
gen y0_1988 = y0_1987 + trend + rnormal(0, 10)
gen y0_1989 = y0_1988 + trend + rnormal(0, 10)
gen y0_1990 = y0_1989 + trend + rnormal(0, 10)
gen y0_1991 = y0_1990 + trend + rnormal(0, 10)
gen y0_1992 = y0_1991 + trend + rnormal(0, 10)

* Reshape data to long format
reshape long y0_, i(id) j(year)
rename y0_ y0

* Determine treatment status in 1990 based on fixed effects
su id if year == 1990, detail
gen treat = 0
replace treat = 1 if id <= `r(p25)' & year == 1990

* Ensure treatment status remains consistent across years
bysort id: egen max_treat = max(treat)
bysort id: replace treat = max_treat

* Post-treatment variable
gen post = 0
replace post = 1 if year >= 1991

* Apply group-specific trends in 1991 and 1992
replace y0 = y0 + 10 if year >= 1991 & group == 2
replace y0 = y0 + 20 if year >= 1991 & group == 3
replace y0 = y0 + 30 if year >= 1991 & group == 4

* Generate y1 by adding treatment effect for treated units
gen y1 = y0
replace y1 = y0 + 300 if year == 1991 & treat == 1
replace y1 = y0 + 600 if year == 1992 & treat == 1

* Treatment effect
gen delta = y1 - y0
label var delta "Treatment effect for unit i (unobservable in the real world)"

sum delta if post == 1, meanonly
gen ate = `r(mean)'
sum delta if treat == 1 & post == 1, meanonly
gen att = `r(mean)'

* Generate observed outcome based on treatment assignment
gen earnings = y0
qui replace earnings = y1 if post == 1 & treat == 1

* Show difference in earnings at baseline between treatment and control
bysort treat: sum earnings if year == 1990 // Check baseline differences between groups

* Illustrate parallel trends assumption
su y0 if treat == 1 & post == 0
gen ey0_10 = `r(mean)'
su y0 if treat == 1 & post == 1
gen ey0_11 = `r(mean)'
su y0 if treat == 0 & post == 0
gen ey0_00 = `r(mean)'
su y0 if treat == 0 & post == 1
gen ey0_01 = `r(mean)'

gen parallel_trends = (ey0_11 - ey0_10) - (ey0_01 - ey0_00)

reg y0 post##treat, robust cluster(state)
su parallel_trends

* Diff-in-diff
su earnings if treat == 1 & post == 0
gen ey_10 = `r(mean)'
su earnings if treat == 1 & post == 1
gen ey_11 = `r(mean)'
su earnings if treat == 0 & post == 0
gen ey_00 = `r(mean)'
su earnings if treat == 0 & post == 1
gen ey_01 = `r(mean)'

gen did = (ey_11 - ey_10) - (ey_01 - ey_00)

reg earnings post##treat, robust cluster(state)
su did att

* Event study regression
reg earnings treat##ib1990.year, cluster(state)

* Generate the coefficient plot
coefplot, keep(1.treat#*) omitted baselevels cirecast(rcap) ///
    rename(1.treat#([0-9]+).year = \1, regex) at(_coef) ///
    yline(0, lp(solid)) xline(1990.5, lpattern(dash)) ///
    xlab(1987(1)1992) ///
    title("Estimated Effect of Training on Earnings") ///
    subtitle("Selection on fixed effects")
	
graph export ./selection_fe_es.png, as(png) replace



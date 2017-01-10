
########

# Author: Amy White
# Date: 12/22/2016

# Purpose: Track who has created events for the Community Meeting to Resist Trump campaign.

# 		Specifically, Gabby and Vikki sent out the mailer https://act.moveon.org/mailings/drafts/compose/175087/
#		to the full membership on 12/22 in the afternoon.  The reply-to address was incorrect so the mailer
# 		was actually stopped before it completed and resent as mailer #175160 so I will include that as well. 

#		All MOMs with id % mod 5303 % mod 2 == 0 were sent to a survey page https://act.moveon.org/survey/cmty-mtgs-interest-survey/?source=peoplesaction
#		where they filled out their information and indicated whether they would be interested in hosting
#       or helping with an event.  They had three choices:
#			- I am interested in hosting a community meeting on Sunday, January 15.
#			- I am interested in helping with a community meeting on Sunday, January 15.
#			- I cannot host a meeting on Sunday, January 15, but I would like to attend if one is organized in my area.
#		and could choose more than one option. 

#		They will immediately be directed to the event page to create the event
#		as well as receiving an email invite to create the event immediately and then reminder emails
#  		over the next week.  This survey is page_id = 4045 in Action Kit. The only way to determine this is to
#		browse through the Pages tab in Action Kit and find the one that matches the title from the website,
#		or you can look at core_clicksurl and search for the URL like below and find the page_id that way.
#				select * from ak_moveon.core_clickurl where url LIKE '%cmty-mtgs-interest-survey%' 

#  		Or you could see which page_ids have the associated mailing_id in the core_action table.  This assumes
#		that there was an action that took place on the page - if there was no action then the page will not 
#		be captured. 
#				select distinct page_id, mailing_id from ak_moveon.core_action where mailing_id = 175087

#		The other half of the MOMs are sent directly to the event creation page and by-pass the survey step.
#		The URL is https://act.moveon.org/event/cmty-mtgs-trump/create/?source=peoplesaction and the page_id = 3989

#		The research questions are (1) are people who are sent to the survey page more likely to create an 
#		event then those who are sent directly to the event creation page, and (2) of those people who are
#		sent to the survey page, how many reminders are required before they actually create the event? 

#		This particular mailer was sent out under Campaign_id = 49.  To determine the campaign associated
#		with the mailer, you can either scroll through the events_campaign table and find your best guess
#		based on title and created_at. Or you can find the event_ids associated with your page_ids
#		from events_eventsignup and join those back to events_event to get the campaign_id associated with the event.


# Data Used: AK_moveon schema tables

# Results:

#########


## (1) Investigating data relationships ##


# Clearing the temporary tables I create
drop table stafftemp.event_respondents
drop table stafftemp.survey_respondents
drop table stafftemp.events_created

# Finding anyone who took action on the events creation page from a link in the mailing. 
create table stafftemp.event_respondents as
select distinct cuc.first_name, cuc.last_name, ca.user_id, min(ca.created_at) as action_created_at, 'event' as action_type
from ak_moveon.core_action ca
join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
where ca.page_id in (3989) AND ca.mailing_id in (175087,175160)
group by cuc.first_name, cuc.last_name, ca.user_id

# Looking at data 
select * from stafftemp.event_respondents order by action_created_at
# 80 obs. 

# Finding anyone who took action in the survey data from a link in the mailing.  Merging
# in the answers from their survey questions and keeping only the answer to the checkbox
# for each person. A person could choose more than one checkbox so selecting distinct user_ids. 
# Including people who said they could attend but not host an event. 
create table stafftemp.survey_respondents as
select distinct cuc.first_name, cuc.last_name, ca.user_id, min(ca.created_at) as action_created_at, 'survey' as action_type
from ak_moveon.core_action ca
join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where ca.page_id in (4045) AND ca.mailing_id in (175087,175160) AND 
      caf.value in('I am interested in hosting a community meeting on Sunday, January 15.',
               'I am interested in helping with a community meeting on Sunday, January 15.',
               'I cannot host a meeting on Sunday, January 15, but I would like to attend if one is organized in my area.')
group by cuc.first_name, cuc.last_name, ca.user_id 

# Looking at data
select * from stafftemp.survey_respondents order by action_created_at 
# 1138 obs

# Now finding any events that were created for this campaign and merging in whether they were created
# by survey people or direct event creation people
create table stafftemp.events_created as
select coalesce(sr.first_name, er.first_name) as first_name,
		coalesce(sr.last_name, er.last_name) as last_name,
		ee.creator_id as user_id,
		ee.id as event_id, 
		ee.created_at,
		ee.title,
		ee.status,
	CASE 
		WHEN MOD(MOD(ee.creator_id, 5303),2) = 0 THEN 'survey' 
		ELSE 'event_host' 
	END as mailer_type,
	coalesce(sr.action_type, er.action_type) as action_type,
	coalesce(sr.action_created_at, er.action_created_at) as action_created_at
from ak_moveon.events_event ee 
left join stafftemp.survey_respondents sr on ee.creator_id = sr.user_id
left join stafftemp.event_respondents er on ee.creator_id = er.user_id
where ee.campaign_id = 49

# Looking at data
select * from stafftemp.events_created order by created_at
# 442 events created

# Testing if any of the events that were created did not come from either people who 
# followed the link from the mailer or people who completed the survey.
select * from stafftemp.events_created
where action_type IS NULL
order by created_at desc
# 82 of them....

# How many of these are from the survey mailer? 
select count(distinct user_id) from stafftemp.events_created
where action_type IS NULL AND mailer_type = 'survey'
# 48 people

# Looking at the actions created by these 19 people. 
select cuc.first_name, cuc.last_name, ca.*, caf.name, caf.value
from (
	  select distinct user_id from stafftemp.events_created
	  where action_type IS NULL AND mailer_type = 'survey'
	 ) 
left join ak_moveon.core_action ca USING (user_id)
left join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where ca.created_at > '2016-12-21'
order by user_id
# It looks like these people who were sent to the survey page clicked
# on the create event now link and skipped filling out the survey all together.
# They have missing mailing_ids and page_ids equal to 3989, the page for creating
# an event now.  They also have core_actionfield referrer value equal to the 
# survey website where they initially landed. 
      
# Making sure this is true for all 19 of these people
select distinct cuc.first_name, cuc.last_name, ca.user_id
from (
	  select distinct user_id from stafftemp.events_created
	  where action_type IS NULL AND mailer_type = 'survey'
	 ) 
left join ak_moveon.core_action ca USING (user_id)
left join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where ca.page_id = 3989 AND caf.name = 'referrer' AND caf.value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey/?source=peoplesaction%'
# This is true for 16 of the 19 people.... 

# Looking at the other three.
select cuc.first_name, cuc.last_name, ca.*, caf.name, caf.value
from (
	  select distinct user_id from stafftemp.events_created
	  where action_type IS NULL AND mailer_type = 'survey'
	 ) 
left join ak_moveon.core_action ca USING (user_id)
left join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
left join( 
        select distinct ca.user_id
        from (
              select distinct user_id from stafftemp.events_created
              where action_type IS NULL AND mailer_type = 'survey'
             ) 
        left join ak_moveon.core_action ca USING (user_id)
        left join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
        left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
        where ca.page_id = 3989 AND caf.name = 'referrer' AND caf.value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey/?source=peoplesaction%'
) as explained USING (user_id)
where explained.user_id IS NULL AND ca.created_at > '2016-12-21'
# The other two have referrer values of https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey 
# where it looks like they completed the survey and then clicked on the link to create their
# event now.  It's weird though that they were able to make it to the thank you page without
# selecting any of the check boxes.... or at least the core_actionfield table doesn't show
# them selecting any of these values.  

# Finding all people who show up in the 3989 page but not in the 4045 page
select *
from (
    select distinct ca.user_id
	from ak_moveon.core_action ca
	left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
	where (ca.page_id = 4045) 
) as one
          
right join (
    select *
	from ak_moveon.core_action ca
	left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
	where (ca.page_id = 3989 AND (caf.value LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' OR 
	    	                      caf.value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%'))
  ) as two USING (user_id)
where one.user_id IS NULL


# One of them was Matt Blisic (a MoveOn staffer) who had a referring_user_id 
# I'll look at the other two to make sure they didn't complete the question box
# on the survey
select ca.*, caf.name, caf.value
from ak_moveon.core_action ca
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where ca.user_id in(35590637,35096152) AND ca.created_at > '2016-12-21' 
order by ca.user_id
# Nope, they somehow got to the thank-you page without first going answering
# the survey question. 

# Now looking at people who came from the event_host mailer but didn't show up in 
# my initial query of event_respondents. 
select count(distinct user_id) from stafftemp.events_created
where action_type IS NULL AND mailer_type = 'event_host'
# 9 of them.

# Looking at their actions.
select cuc.first_name, cuc.last_name, ca.*, caf.name, caf.value
from (
	  select distinct user_id from stafftemp.events_created
	  where action_type IS NULL AND mailer_type = 'event_host'
	 ) 
left join ak_moveon.core_action ca USING (user_id)
left join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where ca.created_at > '2016-12-21'
order by user_id
# That's very odd.  It looks like 6 of these people came from the survey thank-you page
# and one came from the survey page.  These people should not have gone to the survey page at
# all....?? Perhaps they have two email addresses in our database, one of which got the event host
# email, and one of which got the survey email.  They followed the link to the survey page
# but then entered the other email on the form.  Milan says it's not uncommon for people to 
# have multiple email addresses in our system so it's not unreasonable to think this is what
# is happening. 
# Two people don't have this - one has source = conf (??) and one is Jadzia.  

# I'm not sure how I will handle these mixed up people in my analysis....

# Verifying that for any event that is created under this campaign, the person must have had
# an action on the 3989 page, and for any action on the 3989 page, there must be a corresponding
# event from that user_id
select ee.creator_id, ca.user_id
from (
	select distinct creator_id
	from ak_moveon.events_event
	where campaign_id = 49
) as ee
full outer join (
	select distinct user_id
	from ak_moveon.core_action
	where page_id = 3989
) as ca on ee.creator_id = ca.user_id
where ee.creator_id IS NULL OR ca.user_id IS NULL
# There are 11 records where the person had a 3989 action but no event was created...

# For example, 
select *
from ak_moveon.core_action ca
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where page_id = 3989 AND user_id in(9728056, 35649706, 35649647, 4363364)

select * 
from ak_moveon.events_event
where creator_id in(9728056, 35649706, 35649647, 4363364)
# I sent a bug note to AK to see why this might happen because Scott said he
# didn't think it should occur. I turns out what happens is people can join 
# an event as a participant and then be made into a host. It's not clear why they end up 
# having a record on the 3989 page but that is what is happening to these folks. The AK
# folks said using the creator_id in the events_event table is the most reliable way 
# to identify who created an event. 

## (2) Creating query to identify people who have submitted survey but not created an event yet ##


# Clearing the temporary tables I created
drop table stafftemp.event_respondents
drop table stafftemp.survey_respondents
drop table stafftemp.events_created

# Finding all people who submitted information on the survey page.  I'm identifying these people
# by finding anyone who has an action on page 4045 (the survey page) OR has an action on 
# 3989 (the event creation page) with a referral coming from the survey page since 
# the page 4045 info may be overwritten if they click to move onto the event creation page. 
create table stafftemp.survey_respondents as
select distinct ca.user_id, cuc.first_name, cuc.last_name, ca.page_id, min(ca.created_at) as action_created_at, 'survey' as action_type,
	CASE 
		WHEN MOD(MOD(ca.user_id, 5303),2) = 0 THEN 'survey' 
		ELSE 'event_host' 
	END as mailer_type
from ak_moveon.core_action ca
join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where (ca.page_id = 4045 AND ca.mailing_id in (175087,175160)) OR 
	  (ca.page_id = 3989 AND (caf.value LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' OR 
	                          caf.value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%'))
group by cuc.first_name, cuc.last_name, ca.user_id, ca.page_id
# Took about 6 minutes to run.... 

# Looking at data
select * from stafftemp.survey_respondents
# 854 obs. 

# Checking that everyone is distinct - the only way they wouldn't be is if they had
# a page_id of 4045 AND 3989. 
select distinct user_id
from stafftemp.survey_respondents
# 805 damn it.  Some people DO have both??!!

select * 
from (
	select distinct user_id
	from stafftemp.survey_respondents
	group by user_id
	having count(*) > 1
	) as dups
left join stafftemp.survey_respondents USING (user_id)
order by user_id, page_id
# Yup, these people have records from both pages.... 

# Looking at their complete action information
select * 
from (
	select distinct user_id
	from stafftemp.survey_respondents
	group by user_id
	having count(*) > 1
	) as dups
left join ak_moveon.core_action ca USING (user_id)
left join ak_moveon.core_actionfield caf ON ca.id = caf.parent_id
where ca.page_id IN(3989,4045)
order by dups.user_id, ca.page_id
# Arg.  So it looks like some people's survey information is overwritten because
# then end up on page 3989 from the survey page but have no survey responses recorded,
# while others capture both steps (like these people).  I mentioned this to techsupport
# and Cody filed a bug with Action Kit so we'll see what they say about it.
# UPDATE: These people likely completed the survey with one AKID and then created the 
# event with a different AKID.  In the referral URL you can see that a different AKID is listed
# than the AKID of the person with the 3989 page.  

# Once again, finding all people who submitted information on the survey page as above.
# I've excluded page_id from the query so I get truly distinct people.  I'm identifying these people
# by finding anyone who has an action on page 4045 (the survey page) OR has an action on 
# 3989 (the event creation page) with a referral coming from the survey page since 
# the page 4045 info may be overwritten if they click to move onto the event creation page.

# Dropping old table
drop table stafftemp.survey_respondents 
 
create table stafftemp.survey_respondents as
select distinct ca.user_id, cuc.first_name, cuc.last_name, min(ca.created_at) as action_created_at, 'survey' as action_type,
	CASE 
		WHEN MOD(MOD(ca.user_id, 5303),2) = 0 THEN 'survey' 
		ELSE 'event_host' 
	END as mailer_type
from ak_moveon.core_action ca
join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where (ca.page_id = 4045 AND ca.mailing_id in (175087,175160)) OR 
	  (ca.page_id = 3989 AND (caf.value LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' OR 
	                          caf.value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%'))
group by cuc.first_name, cuc.last_name, ca.user_id

# Is it the case that people could land on 4045 but not have the mailing IDs listed?
select cuc.first_name, cuc.last_name, ca.*, caf.*
from ak_moveon.core_action ca
join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where ca.page_id = 4045 AND (ca.mailing_id NOT IN(175087,175160) OR ca.mailing_id IS NULL)
order by ca.user_id, ca.created_at
# NOTE - PostgreSQL does not treat Null as a number so if you do mailing_id <> 1000 then it 
# will NOT return values where mailing_id is Null because the evaluation of the <> expression
# returns "unknown" but the query only returns values where the expression returns "true"
# Yes - 97 records.  Interesting.  Most of these are coming from Facebook shares, some from 
# "website" (like our moveon.org website??) and others have source "peoplesaction" like all
# the people from the mailer but they don't have a mailer ID or a referral value.  Not sure
# how these people got there - maybe by copying and pasting the link instead of clicking on it....
# My records are in this final category and I went to the survey webpage just by entering in
# the URL rather than clicking from a mailer.  
# So the question becomes, again, how to handle these people in my study?  Many of the folks
# from the Facebook shares appear to be new members!  I suppose in the name of getting the 
# most event sign ups, I should go ahead and include these people in the reminder email 
# population if they haven't created an event yet.  Then I'll decide later how I want to
# treat them in my analysis. 

# Therefore, I will exclude the mailing_id requirement from my query to identify survey respondents.
drop table stafftemp.survey_respondents

create table stafftemp.survey_respondents as
select distinct ca.user_id, cuc.first_name, cuc.last_name, min(ca.created_at) as action_created_at, 'survey' as action_type,
	CASE 
		WHEN MOD(MOD(ca.user_id, 5303),2) = 0 THEN 'survey' 
		ELSE 'event_host' 
	END as mailer_type
from ak_moveon.core_action ca
join ak_moveon_modified.core_user_clean cuc on ca.user_id = cuc.id
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where (ca.page_id = 4045) OR 
	  (ca.page_id = 3989 AND (caf.value LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' OR 
	                          caf.value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%'))
group by cuc.first_name, cuc.last_name, ca.user_id


# Looking at data
select * from stafftemp.survey_respondents
# 891 now 

select distinct user_id
from stafftemp.survey_respondents
# 891 - good

select * from stafftemp.survey_respondents
where mailer_type = 'event_host'
# There are 50 people who should have gotten the other mailer but ended up submitting the survey.
# Again, I'm not sure how to handle these people in my analysis...  And should they get follow up 
# emails?  I don't think they should... but I guess I will go ahead and treat them as survey 
# people...  

# Now finding any events that were created for this campaign keeping all survey folks who did NOT
# create an event. I am keeping the people who got the event_host email but ended up submitting the 
# survey. 
select ee.creator_id as id,
		first_name,
		last_name,
		ee.id as event_id, 
		ee.created_at,
		ee.title,
		ee.status,
		mailer_type,
        action_created_at as survey_created_at
from stafftemp.survey_respondents sr 
left join ak_moveon.events_event ee on ee.creator_id = sr.user_id
where ee.campaign_id = 49 AND created_at > '2016-12-21'
order by created_at
# 96 events were created by these people

select sr.*
from stafftemp.survey_respondents sr
left join (
			select distinct creator_id as user_id
			from ak_moveon.events_event 
			where campaign_id = 49 AND created_at > '2016-12-21'
		  ) as events USING (user_id)
where events.user_id IS NULL  AND action_created_at > '2016-12-21'
# 785 people

# Now doing same thing but in one single query that I can give to Vicki

select survey.user_id as id

-- People who visited survey page
from (
	select distinct ca.user_id
	from ak_moveon.core_action ca
	left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
	where ((ca.page_id = 4045) OR 
		  (ca.page_id = 3989 AND (caf.value LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' OR 
	    	                      caf.value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%')))
	       AND created_at > '2016-12-21'
	) as survey
	
-- People who created an event
left join (
			select distinct creator_id as user_id
			from ak_moveon.events_event 
			where campaign_id = 49 AND created_at > '2016-12-21'
		  ) as events USING (user_id)
		  
-- Keeping only people who visited the survey page but did not create an event
where events.user_id IS NULL
# This was saved as a redash query and shared with Vicki
# http://redash.moveon.casa/queries/1802/source

# Clearing the temporary tables I created
drop table stafftemp.event_respondents
drop table stafftemp.survey_respondents
drop table stafftemp.events_created



### (3) Trying to nail down the timing of the event creation for people who came via the survey ###


# Identifying people who visited survey page
create table stafftemp.survey_respondents as
select distinct ca.user_id
from ak_moveon.core_action ca
left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
where ((ca.page_id = 4045) OR 
		  (ca.page_id = 3989 AND (caf.value LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' OR 
	    	                      caf.value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%')))
       AND created_at > '2016-12-21'

select count(*) from stafftemp.survey_respondents
# 1,277

# Looking at the events created by these people
select ee.* 
from ak_moveon.events_event ee
join stafftemp.survey_respondents sr ON sr.user_id = ee.creator_id
where campaign_id = 49
# Need to make sure using the campaign id is sufficient limitation to exclude
# all other events created elsewhere...
# 217 events created

# Looking at the event creation actions taken by these people
select ca.*, caf.*
from ak_moveon.core_action ca
join stafftemp.survey_respondents sr USING (user_id)
left join (
  select * 
  from ak_moveon.core_actionfield 
  where name = 'referrer'
) as caf ON caf.parent_id = ca.id
where page_id = 3989
order by user_id
# 218 actions
# There are some people who have a source of 'conf' instead of peoplesaction and who 
# therefore have no referral information.  I'm not sure what the deal is with these people

# Did all the people who landed on the events creation page 3989 actually end up 
# creating an event or is it possible to have a record with 3989 but no events_event record?
# (See code above that checked this - there were 11 people who had a page 3989 action but 
# no event was created.  I emailed AK about this.)

# Did each person create only one event? 
select distinct creator_id, count(*) as event_ct
from ak_moveon.events_event
where campaign_id = 49
group by creator_id
having count(*) > 1
# It looks like some of these were canceled or deleted... I will limit my 
# queries to exclude non-active events. 

select distinct status
from ak_moveon.events_event
# The possible values are deleted, cancelled, and active. 

# Checking again to make sure each person created only one active event.
select distinct creator_id, count(*) as event_ct
from ak_moveon.events_event
where campaign_id = 49 AND status = 'active'
group by creator_id
having count(*) > 1
# There are still 14 duplicates here. 

select *
from ak_moveon.events_event 
where creator_id IN(2462694, 5814873, 35449224, 33630733, 24990185, 35626369) AND campaign_id = 49
order by creator_id 
# It looks like sometimes an event gets duplicated if the SupportCorps volunteer makes any
# changes like going from public to private or confirming a host. I asked the tech team 
# whether this is normal or not.  In another case it looks like the person may have accidentally
# created the event twice.  They investigated and said that a new event is not created when
# SupportCorps edit an event (as I suspected).  Instead, what is happening here is people are likely
# hitting the back button after submitting an event, making some edits, and then resubmitting.
# This ends up creating a new event (at almost the same time as the original and in consecutive
# event IDs).  Not sure there's a great way to handle this.  Sky added a button on the webpage
# that took people to a page where they could edit their event and told them to not hit the back 
# button which should reduce the occurrences.  

# Now joining together information about where a person came from via the survey with 
# their event creation action.  Keeping all survey and non-survey folks. 

################
### THIS IS THE TABLE I WILL NEED TO UPDATE AS THE REMINDER EMAILS OCCUR - SPECIFICALLY WILL
### NEED TO CHANGE THE EVENT_CREATION_SOURCE TO REFLECT THE REMINDER EMAILS EITHER VIA MAILING_IDS
### IF POSSIBLE OR VIA THE TIMING OF THE REMINDER EMAILS AND THE EVENT CREATION. 
################
--create table stafftemp.events_created as
create temp table events_created as
select coalesce(action.user_id,survey.user_id) as user_id, action.id as action_id,
       action.created_at as action_created_at, action.value, action.mailing_id, action.link, action.source, 
       events.created_event,
       survey.visited_survey_page,
		CASE 
			WHEN MOD(MOD(coalesce(action.user_id,survey.user_id), 5303),2) = 0 THEN 'survey' 
			ELSE 'event_host' 
		END as mailer_type,
		CASE
			WHEN value LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' then 'survey thank you page link'
			WHEN value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%' then 'survey page link'
			WHEN value LIKE '%http%://act.moveon.org/event/cmty-mt%-trump%/%/host%' then 'host edit page'
			WHEN mailing_id in (175087,175160) then 'event_host mailer' -- Some of these have non-NULL values for the 'value' variable like yahoo or outlook mail pages. 
			WHEN mailing_id = 175191 then 'survey reminder email'
			WHEN source = 'conf' AND visited_survey_page = 1 then 'survey thank you emailer' -- Some of these have non-null values for the 'value' variable like yahoo or outlook mail pages
			WHEN created_event IS NULL then 'NA'
			WHEN value LIKE 'http://act.moveon.org/event/cmty-mtgs-trump/search/' then 'event search page'
			ELSE 'unknown'
		END as event_creation_source
		--,trans.transactional_mailing_id

-- All people who visited event creation page. This will include some people who didn't end up creating an event
-- per my investigations above...  
from (
	select ca.*, caf.value
	from ak_moveon.core_action ca
	left join (
	  select * 
	  from ak_moveon.core_actionfield 
	  where name = 'referrer'
	) as caf ON caf.parent_id = ca.id
	where page_id = 3989
	order by user_id
) as action

-- Limiting to only people who actually created an event that is still active.
join (
    select distinct creator_id, 1 as created_event
    from ak_moveon.events_event
    where campaign_id = 49 AND status = 'active'
) as events ON events.creator_id = action.user_id

-- All people who visited survey page
full outer join (
	select distinct ca.user_id, 1 as visited_survey_page
	from ak_moveon.core_action ca
	left join ak_moveon.core_actionfield caf on caf.parent_id = ca.id
	where ((ca.page_id = 4045) OR 
		  (ca.page_id = 3989 AND (caf.value LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' OR 
	    	                      caf.value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%')))
) as survey ON action.user_id = survey.user_id



order by coalesce(action.user_id, survey.user_id)



-- Merging in with information from transactional mailings (i.e. automatic email responses that happen after an action
-- is taken).  The table core_transactionalmailingaction shows actions that occurred as a result of a transactional 
-- mailing.  Thus, we can see if a person clicked on the confirmation email after submitting their survey in order
-- to create their event. These transactional tables are NOT captured in redash so we have to do the MySQL
-- back-end terminal approach to use them. 
left join (
    select ca.id as action_id, transactional_mailing_id
    from (
        select id
        from ak_moveon.core_action
        where page_id = 3989
    ) as ca
    join ak_moveon.core_transactionalmailingaction tma ON ca.id = tma.action_id
    join ak_moveon.core_transactionalmailingsent tms ON tma.transactional_mailing_sent_id = tms.id
) as trans ON action.id = trans.action_id




# Looking at data
select * from stafftemp.events_created 

select * from stafftemp.events_created
where event_creation_source = 'unknown' AND created_event = 1
# 24 events - some of these came from Facebook, 
# some from admin or the dashboard (ones that we created to test), others I have 
# no idea. 

# Looking at where people came from who created an event via the survey page
select * from stafftemp.events_created
where visited_survey_page = 1 and created_event = 1 and 
		value NOT LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' AND
		value NOT LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%'
# This excludes records where value IS NULL.  Many of these people have values like 
# 	https://act.moveon.org/event/cmty-mtgs-trump/5645/host/ where it looks like they went 
# to their host page and made some edit to the event.  When this edit occurs, the event
# record is updated with a new updated_at time stamp and the value information is overwritten. 
# Therefore, it's not obvious where the person came from when they first created the event...
# This seems to imply that the values column is not really reliable for identifying where a 
# person came from which is pretty disappointing... 

# See for example this person:
select * 
from ak_moveon.core_action ca
left join ak_moveon.core_actionfield caf on ca.id = caf.parent_id
where user_id = 35410327 AND ca.created_at > '2016-12-21'
# They completed the survey information and created an event but we can't tell 
# whether they created the event from the link on the thank-you page after the survey,
# from the link on the survey page itself, or from the link in the thank-you email because
# the person modified their event at a later time and that modification referral information
# is what is retained.  

# How many events were created? 
select count(*) as event_ct 
from ak_moveon.events_event
where campaign_id = 49 AND status = 'active'
# 431 events

select count(*) as event_ct
from stafftemp.events_created
where created_event = 1 
# 438 obs - not good....

# How many events were created from survey vs event host mailers?
select distinct mailer_type, count(*) 
from stafftemp.events_created
where created_event = 1
group by mailer_type
# Event_host 142
# Survey 137

# But what if you look at people who visited the survey page vs people who didn't?
select distinct visited_survey_page, count(*) 
from stafftemp.events_created
where created_event = 1
group by visited_survey_page
# NULL 138
# 1 141
# So then the distributions actually flip.  But in either case, they are almost identical
# so sending someone to the survey page vs to create an event immediately so far has no
# significant impact. 

# For those people who did get sent to the survey page, at what point did they create the event?
# Checking unknown sources
select * from stafftemp.events_created where source = 'conf'
order by event_creation_source
# These are all host edit pages or unknowns.  I think these are from confirmation emails
# either from after a person created an event, or after a person submitted the survey.
# There are, however, two people who did not visit the survey page and did not 
# come from the host edit page but who had conf sources.... I wonder if these are 
# issues with people having more than one email in our system... 

# What are these people's names?
select first_name, last_name, id
from ak_moveon_modified.core_user_clean
where id in(35628991,35623202)
# Ellen Wagner 35628991
# Joyce Yu 35623202

# Are there other people in our system with the same names?
select first_name, last_name, id as user_id
from ak_moveon_modified.core_user_clean 
where (first_name = 'Ellen' and last_name = 'Wagner') OR
	  (first_name = 'Joyce' and last_name = 'Yu')
# Yes, there are quite a lot of them.

# Did any of these other people with the same names ever complete the survey page? 
select names.*, ca.*
from ak_moveon.core_action ca
join (
	select first_name, last_name, id as user_id
	from ak_moveon_modified.core_user_clean 
	where (first_name = 'Ellen' and last_name = 'Wagner') OR
	  	  (first_name = 'Joyce' and last_name = 'Yu')
) as names USING (user_id)
where page_id = 4045
# Yes, in fact they did!  
# Ellen Wagner 18,955,954
# Joyce Yu 19,487,114
# So this makes my analysis particularly messy since I'm not capturing

# Looking at breakdown of when events were created
select distinct mailer_type, visited_survey_page, event_creation_source, count(*) as rec_ct
from stafftemp.events_created
where created_event = 1
group by 1, 2, 3
order by 1, 2, 3

################
# I REPORTED THESE NUMBERS TO THE EMAIL CHAIN ON THIS TOPIC.  WILL UPDATE AS THEY DO THE 
# REMINDER EMAILS. 
################
# Summing events created based on mailer associated with the AKID that created the event
select distinct mailer_type, count(*)
from stafftemp.events_created
where created_event = 1
group by 1 
# MAILER_TYPE	COUNT
# event_host	236
# survey	224

# Now summing events based on whether the person visited the survey page
select distinct visited_survey_page, count(*)
from stafftemp.events_created
where created_event = 1
group by 1
# VISITED_SURVEY_PAGE	COUNT
# 1	220
#   240

# This only captures people who followed a link from the survey page or survey thank-you
# page and then created an event under a different AKID.  It does not capture people like
# Joyce Yu or Ellen Wagner who may have visited the survey page under one AKID and then got
# to the event page somehow without creating a trail from the survey page.  This may have
# occurred when they clicked on the confirmation email and then used their other AKID to 
# create the event. 
################


select * 
from ak_moveon.core_transactionalmailingsent
where action_id IN(142252293, 142258133, 142258134)

select * 
from ak_moveon.core_transactionalmailing
where id IN(725,733)


create table stafftemp.actions_taken as


select *
from (
    select id
    from ak_moveon.core_action
    where page_id = 3989
) as ca
join ak_moveon.core_transactionalmailingaction tma ON ca.id = tma.action_id
join ak_moveon.core_transactionalmailingsent tms ON tma.transactional_mailing_sent_id = tms.id

# Again, keeping only select variables
create table stafftemp.transactional_mailings as
select ca.id as action_id, transactional_mailing_id
from (
    select id
    from ak_moveon.core_action
    where page_id = 3989
) as ca
join ak_moveon.core_transactionalmailingaction tma ON ca.id = tma.action_id
join ak_moveon.core_transactionalmailingsent tms ON tma.transactional_mailing_sent_id = tms.id



## (4) Looking at open and click rates of the two original mailers ##


# Looking at how many people from the survey mailer clicked the link vs the number of people
# from the event_host mailer. 
select distinct link_number,
		CASE 
			WHEN MOD(MOD(user_id, 5303),2) = 0 THEN 'survey' 
			ELSE 'event_host' 
		END as mailer_type,
		url, count(distinct user_id) as url_ct -- counting each person's click to a given URL only once
from ak_moveon.core_click cc
left join ak_moveon.core_clickurl ccu ON ccu.id = cc.clickurl_id
where mailing_id IN(175160,175087),
group by link_number, url, mailer_type
order by link_number, url, mailer_type
# So there are the odd link numbers 1001 - 1004 but putting those aside, it looks like 1436+998 = 2434 survey folks
# clicked the link while 1498+981=2479 event folks clicked the link. 

# How about the open rate? 
SELECT distinct
        CASE 
			WHEN MOD(MOD(user_id, 5303),2) = 0 THEN 'survey' 
			ELSE 'event_host' 
		END as mailer_type,
		COUNT(DISTINCT user_id) as open_ct
FROM ak_moveon.core_open 
WHERE mailing_id IN(175160,175087)
group by mailer_type
# MAILER_TYPE	OPEN_CT
# event_host	358,467
# survey	    356,782

# MAILER_TYPE	Events Created  Mailer Link Clicks   % of Clicks that Resulted in Event
# event_host	236             2479                  9.5%
# survey	    224             2434                  9.2%           




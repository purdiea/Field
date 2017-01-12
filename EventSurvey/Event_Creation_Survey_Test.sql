----------------

-- Author: Amy White
-- Date: 1/11/2017

-- Purpose: Track who has created events for the Community Meeting to Resist Trump campaign. Test whether people sent to a survey page first were more likely to create an event than people who were sent directly to the event creation page. For those people sent to the survey page, at what point (i.e. after how many reminders) did they actually create the event? 

-- Details: Gabby and Vikki sent out the mailer 175087 and 175160 to the full membership on 12/22 in the afternoon. (The reply-to address was incorrect on the first one so the mailer was actually stopped before it completed and resent as the second version.)  

-- All MOMs with id % mod 5303 % mod 2 == 0 were sent to a survey page https://act.moveon.org/survey/cmty-mtgs-interest-survey/?source=peoplesaction (page_id = 4045) while == 1 were sent directly to the event page (page_id = 3989). These are under campaign_id = 49. 

-- Those sent to the survey page who did not create an event will receive follow up emails and contacts to encourage them to create an event. 

-- There are multiple points at which a survey individual could have created an event:
-- (1) From a link on the survey page.  (They can click this without submitting the survey and thus will have
-- no action of visiting the survey page.)
-- (2) From a link on the thank you page after submitting the survey
-- (3) From a link in the confirmation email sent after submitting the survey
-- (4) From the link in the reminder email sent 12/30 (mailing_id 175191) 
-- (5) From a link in the kicker sent to everyone (which directed everyone to the events page, skipping the mod split of the population). 
-- (6) From other ways like Facebook shares, forwarded emails, or visiting the website. 

-- Data Used: AK_moveon schema tables

-- Results: Saved on Wiki https://sites.google.com/a/moveon.org/moveon-wiki/analytics/field/analysis/survey 

------------------


---- (1) Investigating data relationships ----

-- I have deleted most of the code that investigated the data. See earlier commits for details. Here are the primary findings:

-- (i) It is possible for people to submit a survey using one email and then create the event using a different email.  This can manifest itself as people who have event creation actions with referrals from the survey page but no record of submitting a survey.  The URL in the referral will show the AKID for the referral page which will not match the AKID associated with the event creation. In my analysis, I'm identified "survey" individuals as anyone who took an action on page 4045 (the survey page) OR has an action on 3989 (the event creation page) with a referral coming from the survey page.

-- (ii) I assumed that anyone who had an action on the event creation page 3989 would have a corresponding event in the events table with their AKID as the creator_id.  This is not necessarily the case though for co-hosts.  If a person signs up to attend an event and then is made into a co-host by the primary host, they will have a page 3989 action but they will not show up as a creator of any event. Thus, using the creator_id is the most reliable way to determine who created events rather than who submitted an action on page 3989. 

-- (iii) There were instances of the same person creating multiple (nearly or perfectly duplicate) events. Sky looked into this and said people are likely hitting the back button after submitting an event, making some edits, and then resubmitting. This ends up creating a new event (at almost the same time as the original and in consecutive event IDs).  Sky added a button on the webpage that took people to a page where they could edit their event and told them to not hit the back button which should reduce the occurrences.  


-- (2) Identify people who visited survey page but have not created an event 

-- These people will be targeted with follow up emails. 

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

-- This was saved as a redash query and shared with Vicki
-- http://redash.moveon.casa/queries/1802/source


-- (3) Nailing down the timing of the event creation for people who came via the survey 

-- Testing which transactional mailings are associated with actions taken on the event page
select distinct transactional_mailing_id
from (
select id
from ak_moveon.core_action
where page_id = 3989
) as ca
join ak_moveon.core_transactionalmailingaction tma ON ca.id = tma.action_id
join ak_moveon.core_transactionalmailingsent tms ON tma.transactional_mailing_sent_id = tms.id
-- transactional_mailing_sent_id 725

select * from ak_moveon.core_transactionalmailing
where id = 725
-- This is the confirmation email sent after someone submits the survey on page 4045

drop table stafftemp.events_created

-- Joining together information about where a person came with their event creation action.  
create table stafftemp.events_created as
select coalesce(action.user_id,survey.user_id) as user_id, 
       	action.id as action_id,
       	action.created_at as action_created_at, 
       	action.value, 
       	action.mailing_id, 
       	action.link, 
       	action.source, 
       	events.created_event,
       	survey.visited_survey_page,
	trans.transactional_mailing_id,
	CASE 
		WHEN MOD(MOD(coalesce(action.user_id,survey.user_id), 5303),2) = 0 THEN 'survey' 
		ELSE 'event_host' 
	END as mailer_type,
	
	-- Creating variables that capture when/how the person created the event
	CASE WHEN value LIKE '%https://act.moveon.org/cms/thanks/cmty-mtgs-interest-survey%' then 1 ELSE 0 END 
		as survey_thank_you_link,
	CASE WHEN value LIKE '%https://act.moveon.org/survey/cmty-mtgs-interest-survey%' then 1 ELSE 0 END
		as survey_page_link,
	CASE WHEN mailing_id in (175087,175160) then 1 ELSE 0 END
		as event_host_mailer,
 	CASE WHEN mailing_id = 175191 then 1 ELSE 0 END 
		as survey_reminder_email,
	CASE WHEN trans.transactional_mailing_id = 725 then 1 ELSE 0 END
		as survey_conf_email,
	CASE WHEN created_event IS NULL then 1 ELSE 0 END
		as no_event_created,
	CASE WHEN value LIKE '%act.moveon.org/event/cmty-mtgs-trump/search%' OR 
	          value LIKE '%act.moveon.org/event/cmty-mtgs-trump_attend/search%' then 1 ELSE 0 END
		as event_search_page,
	CASE WHEN value LIKE '%facebook.com%' then 1 ELSE 0 END
		as facebook,
	CASE WHEN mailing_id IN (175822,175823) then 1 ELSE 0 END
		as kicker_email

-- All people who visited event creation page. This will include some people who didn't end up creating an event
-- per my investigations above regarding co-hosts. 
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

-- Merging in with information from transactional mailings (i.e. automatic email responses that happen after an action
-- is taken).  The table core_transactionalmailingaction shows actions that occurred as a result of a transactional 
-- mailing.  Thus, we can see if a person clicked on the confirmation email (transaction_mailing_sent_id = 725) after 
-- submitting their survey in order to create their event. 
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

order by coalesce(action.user_id, survey.user_id)


-- Checking to make sure each record has exactly 1 source of the event creation
select *
from stafftemp.events_created
where survey_thank_you_link + survey_page_link + survey_reminder_email + survey_conf_email +
	  no_event_created + event_search_page + event_host_mailer + kicker_email + facebook = 0
-- 37 obs. These are mostly values of source = website with google as the value, or a value showing a host
-- event page where it looks like they went and made some updates. 

select *
from stafftemp.events_created
where survey_thank_you_link + survey_page_link + survey_reminder_email + survey_conf_email +
	  no_event_created + event_search_page + event_host_mailer + kicker_email + facebook > 1
-- 2 obs.  They had Facebook as well as the original mailer.  Not sure how this works....

-- How many total events were created?
select count(*) 
from stafftemp.events_created
where created_event = 1
-- 572.  So we are uncertain about the origin of about 7% of the events.  Not bad. 

-- So what are the tallies??  (This will count the 2 obs above with two sources twice)
select distinct mailer_type, 
		sum(created_event) as events_created,
		sum(event_host_mailer) as event_host_mailer,
		sum(survey_page_link) as survey_page_link,
		sum(survey_thank_you_link) as survey_thank_you_link,
    		sum(survey_conf_email) as survey_conf_email,
		sum(survey_reminder_email) as survey_reminder_email,
		sum(kicker_email) as kicker_email,
		sum(event_search_page) as event_search_page,
		sum(facebook) as facebook
from stafftemp.events_created
group by mailer_type
-- I exported this table and reformatted it to include in my reportback. 

-- Again but looking by whether the person ever visited the survey page even if they weren't 
-- sent the original survey mailer
select distinct visited_survey_page, 
		sum(created_event) as events_created,
		sum(event_host_mailer) as event_host_mailer,
		sum(survey_page_link) as survey_page_link,
		sum(survey_thank_you_link) as survey_thank_you_link,
    		sum(survey_conf_email) as survey_conf_email,
		sum(survey_reminder_email) as survey_reminder_email,
		sum(kicker_email) as kicker_email,
		sum(event_search_page) as event_search_page,
		sum(facebook) as facebook
from stafftemp.events_created
group by visited_survey_page
-- I exported this table and reformatted it to include in my reportback. 

---- (4) Looking at the click rates of the two original mailers ----


-- Looking at how many people from the survey mailer clicked the link vs the number of people
-- from the event_host mailer. Excluding the odd 1001 - 1004 links and the ones with no link 
-- number that are generally the donation or unsubscribe links.
select distinct CASE 
			WHEN MOD(MOD(user_id, 5303),2) = 0 THEN 'survey' 
			ELSE 'event_host' 
		END as mailer_type,
		url, count(distinct user_id) as url_ct -- counting each person's click to a given URL only once
from ak_moveon.core_click cc
left join ak_moveon.core_clickurl ccu ON ccu.id = cc.clickurl_id
where mailing_id IN(175160,175087) and link_number < 1000 and link_number IS NOT NULL
group by url, mailer_type
order by url, mailer_type
-- 2227 survey and 2239 event host. (These are less than I counted in an earlier report back because
-- I had counted people who clicked different link numbers that lead to the same URL twice.  Now I count them
-- once since I removed link_number from my group-by.)
-- I included these numbers in my final reportback. 

         




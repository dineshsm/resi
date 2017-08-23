/***************************************************************************************************************************************
 * Author     : Erin McGee
 * Date       : 04-Apr-2014
 * Description: This class will be scheduled using 'Schedule Apex' feature of salesforce.
 * Requirement: 23,95 - Lead and Opportunity Transfer or Expiration.
 * History
     Version             : 1.0
     Author Last Updated : Erin McGee 
     PROJECT             : Turnpike
***************************************************************************************************************************************/
global class ScheduleOpportunityTransferAndExpiration implements Schedulable{

/***********************************************************************************************************************************
     * Author     : Erin McGee 
     * Date       : 04-Apr-2014
     * Param      : SchedulableContext 
     * Return     : None
     * Description: This method will start the batch process that (1)Transfers and Expires Opportunity after the timeframe specified on Affiliate Account.
************************************************************************************************************************************/
   global void execute(SchedulableContext sc) {
      OpportunityTransferAndExpirationBatch transferAndExpirationBatchObj = new OpportunityTransferAndExpirationBatch (); 
      database.executebatch(transferAndExpirationBatchObj);
   }
}
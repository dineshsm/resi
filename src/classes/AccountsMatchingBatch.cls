/**
* Class Name: AccountsMatchingBatch
* Author: Pavan Jasthi, Acumen Solutions
* Date: 4/7/2014 
* Description: Batch job for Account matching
*/
global class AccountsMatchingBatch  implements Database.Batchable<sobject>{
	global String Query;
    global Set <String> regionSet;
    global string billingState;
    global static boolean bCatchup=false;
    global integer iLimit;
    global set<ID> accountIds; 
    global final Map <String, ID> divisionMap = new Map <String,ID>();
    global static boolean hasData = false;
    global final Map <String, Group> queueMap = new Map <String, Group>();
    global static integer jobCount ;
    global boolean oddMode=false;
    global integer lastAccountNumber;
    global AccountsMatchingBatch(){

        for(Group g: [Select Id, developerName From Group Where Type = 'Queue']){
			queueMap.put(g.developerName,g);
		}
    }
    
    global Database.QueryLocator start(Database.BatchableContext BC){
        
       String q;
       
       q =  'Select Id, AccountNumber, Last_Install_Date__c, Billing_Account_Number__c, Service_Address__r.Id, Service_Address__r.Region__c, Service_Address__r.Account__c, Service_Address__r.Account__r.Last_Install_Date__c ';
       q+= ' , Service_Address__r.PostalCode__c, Service_Address__r.PostalCode_4__c, Service_Address__r.Name, Service_Address__r.OwnerID , Service_Address__r.Is_Account_Linking_Processed__c, Service_Address__r.Address__c ';
       q += ' from Account  ';
              q+='  where Service_Address__r.Is_Account_Linking_Processed__c =:bCatchup ';
   //           if (regionSet!=null) q+= ' and Service_Address__r.Region__c in :regionSet';
              if (billingState!=null) q+=' and BillingState =:billingState';
          if (accountIds!=null) q+= ' and Id in :accountIds';
     /*       if (lastAccountNumber!=null){
            	q+=' and  Billing_Account_Number__c like \'%'+lastAccountNumber+'\'';
            }
            else {
          if (!oddMode){
          	q+= ' and ( Billing_Account_Number__c like \'%0\'			or Billing_Account_Number__c like \'%2\' 			or Billing_Account_Number__c like \'%4\' 			or Billing_Account_Number__c like \'%6\' 			or Billing_Account_Number__c like \'%8\' )';
          }
          else { 
          q+= ' and ( Billing_Account_Number__c like \'%1\'			or Billing_Account_Number__c like \'%3\' 			or Billing_Account_Number__c like \'%5\' 			or Billing_Account_Number__c like \'%7\' 			or Billing_Account_Number__c like \'%9\' )';
          }
            } */
        if (iLimit!=null) q+=' LIMIT :iLimit';
       Query = q;
       system.debug('query~~~~'+query);
       return Database.getQueryLocator(Query);
    }

    global void execute(Database.BatchableContext BC, sobject[] scope){
		List <Account> accountUpdList = new List<Account>();
		Map <Id, Account> addressAccountMap = new Map <Id, Account>();
	 	Map <Id, Customer_Address__c> updatedAddressMap = new Map <Id, Customer_Address__c>();
	 	AccountMatchManager__c thisManager;
	 	string ammKey = billingState;
	 	if (oddMode) ammKey+='*';
	 	if (lastAccountNumber!=null)  ammKey+='z'+lastAccountNumber;
	 	thisManager= AccountMatchManager__c.getValues(ammKey);
	 	if (thisManager.completed_total__c==null) thisManager.completed_total__c=0;
	 	thisManager.completed_total__c+=scope.size();
        for(sObject s : scope){
        	hasData=true;
            Account o = (Account)s;    
		if (o.Billing_Account_Number__c!=null && o.Service_Address__c!=null ){
            Customer_Address__c addr;
       		/*Start account linking logic*/
            if (o.service_address__r!=null) {
            	 o.Region__c=o.Service_Address__r.Region__c;
	            if (divisionMap.get(o.Region__c)!=null){
				//	o.Division = divisionMap.get(o.Region__c);
				}
            	addr = o.Service_Address__r;
				if (updatedAddressMap.keySet().contains(o.service_address__c)){
					addr = updatedAddressMap.get(o.service_address__c);
					system.debug('1~~~'+addr);
				}
				else {
				 	addr = o.Service_Address__r;
				 	system.debug('2~~~'+addr);
				}
				if (addr.Account__c==null){
					addr.Account__r =o ;
					addr.Account__c=o.id;
					updatedAddressMap.put(addr.id, addr);
					system.debug('3~~~'+addr);
				}
				else {
					if (addr.Account__r.Last_Install_Date__c < o.Last_Install_Date__c){
						addr.Account__r =o ;
						addr.Account__c=o.id;
						updatedAddressMap.put(addr.id, addr);
						system.debug('4~~~'+addr);
					} 
				}
				/*End account linking logic*/
				/*Start merge of address fixing logic*/
	//			if (!addr.Is_Account_Linking_Processed__c){  //dont run this logic if we've already fixed the address
					 if (addr.PostalCode__c!=null){
						string zip9 = addr.PostalCode__c;
							if (zip9.length()==9){
								addr.PostalCode__c=zip9.substring(0,5)+'-'+zip9.substring(5,9);
								addr.PostalCode_4__c=zip9.substring(5,9);
							}
			            }
						if (queueMap.get('Shared_Address_Pool')!=null){
					//		addr.OwnerId=queueMap.get('Shared_Address_Pool').id;
						}
						addr.Name=addr.Address__c;
			            addr.Is_Account_Linking_Processed__c=true; //set flag to avoid reprocessing
			            system.debug('addr~~'+addr);
			            updatedAddressMap.put(addr.id, addr);
				}
				/*End merge of address fixing logic*/
            }
            o.Is_Linking_To_Address_Processed__c=true;  // set flag to avoid reprocessing
           
            accountUpdList.add(o);
     //   	}
        }
        List <sobject> genericUpdateList= new List <sObject>();
        if (!updatedAddressMap.isEmpty()){
        	system.debug('keySet~~~~'+updatedAddressMap.keySet());
        	for (Customer_Address__c ca:updatedAddressMap.values() ){
        		SObject o1 = ca.getSObjectType().newSObject(ca.id);
    //			o1.put('PostalCode__c',ca.PostalCode__c);
 //   			o1.put('PostalCode_4__c',ca.PostalCode_4__c);
    			o1.put('Account__c',ca.Account__c);
    		//	o1.put('OwnerId',ca.OwnerId); Commented per EC 5/23/2014 406 PM
    			o1.put('Name',ca.Name);
    			o1.put('Is_Account_Linking_Processed__c',ca.Is_Account_Linking_Processed__c);
    			genericUpdateList.add(o1);
        	}
      //  	genericUpdateList.add(updatedAddressMap.values());
        //	Database.SaveResult[] srList = Database.update( updatedAddressMap.values(), false);  //if a lock occurs somewhere we only skip those and can reprocess later
        }
            if (!accountUpdList.isEmpty()){
            	for (Account a : accountUpdList){
            		SObject o1 = a.getSObjectType().newSObject(a.id);
    			//	o1.put('Region__c',a.Region__c); Commented per EC 
    			o1.put('Is_Linking_To_Address_Processed__c',a.Is_Linking_To_Address_Processed__c);
    				genericUpdateList.add(o1);
            	}
        	//system.debug('keySet~~~~'+updatedAddressMap.keySet());
        	//Database.SaveResult[] srList =database.update(accountUpdList,false);  //if a lock occurs somewhere we only skip those and can reprocess later
        }
        if (!genericUpdateList.isEmpty()){
        	system.debug('genericUpdateList~~~~'+genericUpdateList);
        	Database.SaveResult[] srList =database.update(genericUpdateList,false);  //if a lock occurs somewhere we only skip those and can reprocess later
        }
        system.debug('hasData~~~'+hasData);
        update thisManager; 
        
    }

    global void finish(Database.BatchableContext BC)
    {
        //BatchUtils.batchEmailSuccess(BC,'Address Matching');
        system.debug('hasData~~~~'+hasData);

        AsyncApexJob ajob = [select JobItemsProcessed from AsyncApexJob where id=:bc.getJobId()];
        system.debug('ajob~~~'+ajob);
        if (ajob.JobItemsProcessed>0){
        	AccountsMatchingBatch a  =new AccountsMatchingBatch();
			a.regionSet = regionSet;
			system.debug('regionSet~~~'+a.regionSet);
			a.billingState=billingState;
			a.oddMode=oddMode;
			a.lastAccountNumber=lastAccountNumber;
			system.debug('billingState~~~'+a.billingState);
			a.iLimit = iLimit;
			id dbid =database.executeBatch(a);
        }
        else { 
        		string ammKey = billingState;
			 	if (oddMode) ammKey+='*';
			 	if (lastAccountNumber!=null)  ammKey+='z'+lastAccountNumber;
			 	AccountMatchManager__c thisManager;
			 	thisManager= AccountMatchManager__c.getValues(ammKey);
        		thisManager.finished__c=true;
        		thisManager.finished_Time__c=system.now();
        		update thisManager; 
        		kickOffJob(iLimit);
        }
    }
    
    global static void sendEmailOnBatchComplete(Database.BatchableContext apexJob, String jobName, Set <String> stateCriteria)
	{
		string msgBody;
		string msgSubject;
		
		AsyncApexJob a = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedBy.Email
						  FROM AsyncApexJob 
						  WHERE Id =:apexJob.getJobId()];
		msgSubject = jobName + ' is Complete';
		if(a.NumberOfErrors > 0)
		{
			msgBody ='<html><body><div style="border: 1px solid #EEE;border-radius:5px;padding:5px;"><h2>'+ jobName +' Failed.</h2><br/><br/>';
		}
		else
		{
			msgBody ='<html><body><div style="border: 1px solid #EEE;border-radius:5px;padding:5px;"><h2>'+ jobName +' processed successfully.</h2><br/><br/>';
		}
		msgBody = msgBody + '<table style="border: 1px solid #EEE;padding:5px;"><tr><td>State:- </td><td>'+ stateCriteria +'</td></tr>';
		msgBody = msgBody + '<table style="border: 1px solid #EEE;padding:5px;"><tr><td>No of Errors:- </td><td>'+ a.NumberOfErrors +'</td></tr>';
		msgBody = msgBody + '<tr><td>Job Items Processed:- </td><td>'+ a.JobItemsProcessed + '</td></tr>';
		msgBody = msgBody + '<tr><td>Total Job Items:- </td><td>'+ a.TotalJobItems + '</td></tr></table></div></body></html>';
			  
		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		String[] toAddresses = new String[] {a.CreatedBy.Email};
		mail.setToAddresses(toAddresses);
		mail.setSubject(msgSubject);
		mail.setHtmlBody(msgBody);
		try{
		   Messaging.sendEmail(new Messaging.SingleEmailMessage[] {mail});
		}
		catch(Exception e){
			System.debug('EMAIL SEND ERROR::>>>> '+e.getMessage());
		}
		
	}
	
	global static boolean canRunJob(){
		 final set<String> batchStatuses = new set<String>{'Queued', 'Preparing', 'Processing'};
	
	 list<AsyncApexJob> activeJobs;
	 if (jobCount==null) {
	 	activeJobs = [SELECT a.Status, a.JobType, a.Id, a.ApexClass.Name, a.ApexClassId 
											FROM AsyncApexJob a 
											WHERE Status IN: batchStatuses AND JobType = 'BatchApex'];
	 
		jobCount	=activeJobs.size();
	 }								
		if (jobCount<ConfigurableParameters__c.getValues('BatchApexJobs').NumberValue__c) return true; 
		else return false;
	}
	 
	
	global static void kickOffJob(integer limitSize){
		
		
		List <AccountMatchManager__c> allMatchers = AccountMatchManager__c.getAll().values();
			jobCount=null;  
			for (AccountMatchManager__c amm: allMatchers){
				if (canRunJob()){
					if (!amm.finished__c&&!amm.started__c){
					AccountsMatchingBatch a  =new AccountsMatchingBatch();
					if (amm.name.contains('*')){
						a.oddMode =true;
					}
					if (amm.name.contains('z')){
						string [] sArray = amm.name.split('z');
						string acctNumb = sArray[1];
						a.lastAccountNumber=integer.valueOf(acctNumb);
						a.billingState= sArray[0].remove('*');
					}
					else {
						a.billingState =amm.name.remove('*');
					}
				
					a.iLimit = limitSize;
					id dbid =database.executeBatch(a);
					jobCount++;
					amm.started__c=true;
					amm.start_time__c=system.now();
					update amm;
					}
				}
				else {
					return;
				}
			}
		
	}
	
}
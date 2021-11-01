CREATE PROCEDURE ARAPTransactionsSP @Period int, @Company uniqueidentifier, @Branch uniqueidentifier, @OrgList varchar(8000)
, @OrgGroupList varchar(8000), @BranchList varchar(8000), @CountryList varchar(8000),@ExCountryList varchar(8000),@SalesRepList varchar(8000), @OverLimitOnly Char(1)
, @AgeingOption char(3), @Day1 int, @Day2 int, @Day3 int, @Day4 int, @AccountsRelationShip varchar(3)
, @ConsolidatedCategory varchar(3), @SalesRepRoll varchar(8000), @SummaryOnly char(1), @LedgerType char(2)
, @AgedByInvoiceDate char(3), @CurrencyList varchar(8000), @IncludeDisbursement char(1)
, @DisbursementTranOnly char(1), @SettlementGroupList varchar(8000), @CreditRating char(3), @ShowInInvoicedCurrency char(1)
, @ShowLocalEquivalentTotal char(1), @ShowAllTransactions char(1), @PaymentStatus char(3), @TransactionTypeList varchar(8000)
, @PostDateFrom smalldatetime, @PostDateTo smalldatetime, @DueDateFrom smalldatetime, @DueDateTo smalldatetime, @InvoiceDateFrom smalldatetime, @InvoiceDateTo smalldatetime
, @NotInActiveBatchTranOnly char(1)		-- Obsolete; will be removed in future work item. Please use @IncludeActiveBatchTran instead.
, @GroupBy varchar(8000), @OrderBy varchar(8000)
, @OrgBranch char(3), @ShowAddUser CHAR(1), @ShowOnlyAggregated CHAR(1), @ShowLineAmounts CHAR(1)
, @CurrentDateTime DateTime
, @OverdueTransactions Char(1) = 1
, @BranchManagementCode VARCHAR(3) = NULL
, @AgreedPaymentMethodList varchar(8000) = ''
, @ExcludeMatchedToFutureRECPAY char(1) = ''
, @FutureRECPAYNotInBalance char(1) = ''
, @IncludeActiveBatchTran char(1) = 'Y'
, @FilterNotActiveBatchTran varchar(8000) = ''
, @ShowMatchStatusAndReason char(1) = ''

as

--------------------------------------------------------------------------------------------
-- @AgedByInvoiceDate : 'INV' = Ageing by Invoice Date, 'DUE' = Ageing by Due Date, 'PST' = Ageing by Post Date, 'NON' = No Ageing
-- @PaymentStatus : 'NON', 'FUL' = Fully Paid, 'PAR' = Part Paid, 'UNP' = Unpaid
--------------------------------------------------------------------------------------------
SET NOCOUNT ON
IF @OverdueTransactions IS  NULL  OR @OverdueTransactions = '' OR @OverdueTransactions <> 'Y' SET @OverdueTransactions = 'N'
DECLARE @CountryCode as char(2)
DECLARE @ReportDate as smalldatetime, @P1PlusStart as smalldatetime, @P2PlusStart as smalldatetime, @P3PlusStart as smalldatetime
DECLARE @PCurrentStart as smalldatetime, @PCurrentEnd as smalldatetime, @P1Start as smalldatetime, @P2Start as smalldatetime, @P3Start as smalldatetime
DECLARE @P4Start as smalldatetime, @IsReciprocal as bit
DECLARE @Today as smalldatetime = CONVERT(varchar, @CurrentDateTime, 101)
DECLARE @UseOutstandingAmount bit = 0

--------------------------------------------------------------------------------------------
-- Init Variables
--------------------------------------------------------------------------------------------
IF (@SummaryOnly is null) SET @SummaryOnly = ''
IF (@SalesRepList is null) SET @SalesRepList = ''
IF (@SalesRepRoll is null) SET @SalesRepRoll = ''
IF (@AccountsRelationShip is null) SET @AccountsRelationShip = ''
IF (@ConsolidatedCategory is null) SET @ConsolidatedCategory = ''
IF (@SettlementGroupList is null) SET @SettlementGroupList = ''
IF (@CreditRating is null) SET @CreditRating = ''

SELECT @CountryCode=(SELECT GC_RN_NKCountryCode FROM GlbCompany WHERE GC_PK = @Company )
SELECT @IsReciprocal = (SELECT GC_IsReciprocal FROM GlbCompany WHERE GC_PK = @Company)

SELECT
	@ReportDate = ReportDate, 
	@P1PlusStart = P1PlusStart, 
	@P2PlusStart = P2PlusStart, 
	@P3PlusStart = P3PlusStart,
	@PCurrentStart = PCurrentStart, 
	@PCurrentEnd = PCurrentEnd, 
	@P1Start = P1Start, 
	@P2Start = P2Start, 
	@P3Start = P3Start,
	@P4Start = P4Start
FROM 
	CalculateDatesForAgeing(@Company, @Period, @AgeingOption, @Day1, @Day2, @Day3, @Day4, @CurrentDateTime)

/*--------------------------------------------------------------------------------------------
-- DEBUG ONLY
--------------------------------------------------------------------------------------------
PRINT '@P3PlusStart: ' + CAST(@P3PlusStart as varchar(200))
PRINT '@P2PlusStart: ' + CAST(@P2PlusStart as varchar(200))
PRINT '@P1PlusStart: ' + CAST(@P1PlusStart as varchar(200))

PRINT '@ReportDate: ' + CAST(@ReportDate as varchar(200))

PRINT '@PCurrentEnd: ' + CAST(@PCurrentEnd as varchar(200))
PRINT '@PCurrentStart: ' + CAST(@PCurrentStart as varchar(200))

PRINT '@P1Start: ' + CAST(@P1Start as varchar(200))
PRINT '@P2Start: ' + CAST(@P2Start as varchar(200))
PRINT '@P3Start: ' + CAST(@P3Start as varchar(200))
PRINT '@P4Start: ' + CAST(@P4Start as varchar(200))
*/--------------------------------------------------------------------------------------------
-- Temp Tables
--------------------------------------------------------------------------------------------

CREATE TABLE #TRANSACTIONS
(
	TransactionPK UNIQUEIDENTIFIER,
	AccountPK UNIQUEIDENTIFIER,
	AccountCode nvarchar(12) COLLATE database_default,
	AccountName nvarchar(100) COLLATE database_default,	
	BranchCode CHAR(3) COLLATE database_default,
	CountryCode CHAR(2) COLLATE database_default,
	CountryName nvarchar(80) COLLATE database_default,
	TransactionType Char(3) COLLATE database_default,
	InvoiceRef varchar(38) COLLATE database_default,
	Description nvarchar(128) COLLATE database_default,
	InvoiceRef2 nvarchar(80) COLLATE database_default,
	ContactInfo varchar(282) COLLATE database_default,
	ContactName nvarchar(256) COLLATE database_default,
	ContactPhoneNo varchar(20) COLLATE database_default,
	OC_OH_AddressOverride UNIQUEIDENTIFIER,
	InvoiceTotal money DEFAULT 0,
	Balance money DEFAULT 0,
	BalanceInLocal money DEFAULT 0,
	DueDate smalldatetime,
	InvoiceDate smalldatetime,
	CurrencyPK UNIQUEIDENTIFIER,
	CurrencyCode char(3) COLLATE database_default,
	CurrencyCode2 char(3) COLLATE database_default,
	NotDue1Total money,
	NotDue2Total money,
	NotDue3Total money,
	NotDue4Total money,
	Period1Total money,
	Period2Total money,
	Period3Total money,
	Period4Total money,
	PeriodCurrent money,
	NotDue1TotalInLocal money,
	NotDue2TotalInLocal money,
	NotDue3TotalInLocal money,
	NotDue4TotalInLocal money,
	Period1TotalInLocal money,
	Period2TotalInLocal money,
	Period3TotalInLocal money,
	Period4TotalInLocal money,
	PeriodCurrentInLocal money,
	SalesRep char(3) COLLATE database_default,
	CreditController char(3) COLLATE database_default,
	CustomerService char(3) COLLATE database_default,
	CreditLimit money DEFAULT 0,
	AccountGroup nvarchar(6) COLLATE database_default,
	OrgBranchCode char(3) COLLATE database_default,
	IsOverLimit char(1) COLLATE database_default,
	ExchangeRate decimal(18, 9),
	IsDSBInvoice char(3) COLLATE database_default,
	DSBCharge money,
	OSTotal money,
	ARCategory char(3) COLLATE database_default,
	ConsolidationCategory char(3) COLLATE database_default,
	SettlementCode varchar(12) COLLATE database_default,
	AccountCode2 nvarchar(12) COLLATE database_default,
	OrgBranchName varchar(100) COLLATE database_default,
	TranBranchName varchar(100) COLLATE database_default,
	SalesRepName nvarchar(256) COLLATE database_default,
	CreditControllerName nvarchar(256) COLLATE database_default,
	CustomerServiceName nvarchar(256) COLLATE database_default,
	SettlementName varchar(100) COLLATE database_default,	
	RXSubUnitRatio int,
	PostDate smalldatetime,
	DepartmentCode char(3) COLLATE database_default,
	FullyPaidDate smalldatetime,
	InvoiceTerm char(15) COLLATE database_default,
	InvoiceExTax money,
	TaxAmount money,
	JobNumber varchar(35)COLLATE database_default,
	TransactionTypeDesc varchar(20)COLLATE database_default,
	OperatorInitials VARCHAR(3) COLLATE database_default,
	LineInvoiceExTaxAmount money,
	LineTaxAmount money,
	ARUseSettlementGroupCreditLimit char(1),
	SettlementGroupCreditLimit money,
	SettlementGroupOutstandingAmount money,
	SettlementGroupOverCreditLimit char(1),
	UsingOrgAsOwnSettlementGroup char(1),
	AgreedPaymentMethod varchar(3),
	AdditionalCompanyName nvarchar(100),
	MatchedInFuturePeriodInLocalCurrency money,
	MatchedInFuturePeriodInInvoiceCurrency money,
	MatchStatus nvarchar(262) COLLATE database_default,
	MatchStatusReason nvarchar(262) COLLATE database_default
)

DECLARE @MatchedBranchFound as char(1) = 'Y'
If (ISNULL(@BranchManagementCode, '') <> '')
BEGIN
	DECLARE @BranchesForSelectedManagementCode as VARCHAR(8000)
	SELECT @BranchesForSelectedManagementCode = COALESCE(@BranchesForSelectedManagementCode + ',', '') + GB_Code 
	FROM GlbBranch
	WHERE  GB_GC = @Company AND GB_AccountingGroupCode = @BranchManagementCode AND 
	(ISNULL(@BranchList,'') = '' OR CHARINDEX(GB_Code, ISNULL(@BranchList,'')) > 0 )  

	IF (ISNULL(@BranchesForSelectedManagementCode, '') = '') SET @MatchedBranchFound = 'N'
	SET @BranchList = @BranchesForSelectedManagementCode

END

--------------------------------------------------------------------------------------------
-- ADD Outstanding Transactions to #TRANSACTIONS
--------------------------------------------------------------------------------------------
IF @ShowAllTransactions = 'Y'
BEGIN

	DECLARE @MinDate as smalldatetime = '1900-01-01 00:00:00'

	IF @PostDateTo = @MinDate
	SET @UseOutstandingAmount = 1

	IF @Period <> ''
	BEGIN
		SET @PostDateFrom = (SELECT AM_StartDate FROM AccPeriodManagement WHERE AM_PERIOD = @Period AND AM_GC_COMPANY = @Company)
		SET @PostDateTo = (SELECT AM_EndDate FROM AccPeriodManagement WHERE AM_PERIOD = @Period AND AM_GC_COMPANY = @Company)
	END

	IF  @PostDateTo <> ''
	BEGIN
		SET @PostDateTo = Convert(varchar, @PostDateTo, 101)
		IF @PostDateTo >= @Today SET @UseOutstandingAmount = 1
		SET @PostDateTo = DateAdd(dd, 1, @PostDateTo)
	END
	
	IF @DueDateTo<>'' SET @DueDateTo = DateAdd(dd, 1, @DueDateTo)

	IF @InvoiceDateTo<>'' SET @InvoiceDateTo = DateAdd(dd, 1, @InvoiceDateTo)
	
	IF @MatchedBranchFound = 'Y'
	BEGIN
		IF @LedgerType = 'AR'
		BEGIN
			INSERT INTO #TRANSACTIONS
				(TransactionPK, AccountPK, TransactionType, TransactionTypeDesc, InvoiceRef, Description, InvoiceRef2, 
				InvoiceTotal, Balance, DueDate, InvoiceDate, AccountCode, AccountCode2, AccountName, BranchCode, CountryCode, CountryName, CurrencyPK, CurrencyCode, CurrencyCode2, CreditLimit, 
				AccountGroup, OrgBranchCode, ExchangeRate, IsDSBInvoice, OSTotal, ARCategory, ConsolidationCategory, SettlementCode, 
				OrgBranchName, TranBranchName, SettlementName, RXSubUnitRatio, PostDate, DepartmentCode, FullyPaidDate, InvoiceTerm,
				InvoiceExTax, TaxAmount, JobNumber, OperatorInitials, AgreedPaymentMethod, MatchStatus, MatchStatusReason)

				SELECT 
					AH_PK, 
					AH_OH, 
					AH_TransactionType,
					CASE AH_TransactionType
						WHEN 'INV' THEN 'Invoice'
						WHEN 'CRD' THEN 'Credit Notes'
						WHEN 'ADJ' THEN 'Adjustment Notes'
						WHEN 'JNL' THEN 'Journals'
						WHEN 'CTR' THEN 'Contras'
						WHEN 'TRF' THEN 'Transfers'
						WHEN 'REC' THEN 'Receipts'
						WHEN 'PAY' THEN 'Payments'
						WHEN 'EXX' THEN 'Exchanges'
						WHEN 'DSC' THEN 'Discounts'
						WHEN 'OVP' THEN 'Overpayments'
					END, AH_TransactionNum, AH_Desc, 
					AccTransactionHeader.AH_ConsolidatedInvoiceRef,
					AH_LocalTotal,
					CASE @UseOutstandingAmount WHEN 1 THEN AH_OutstandingAmount  
						ELSE AH_LocalTotal - ISNULL(AccTransactionMatchLink.TotalAP_Amount, 0) END,
					AH_DueDate, 
					AH_InvoiceDate, 
					OrgHeader.OH_Code, 
					OrgHeader.OH_Code, 
					OrgHeader.OH_FullName,		
					TranBranch.GB_Code,
					RN_CODE,
					RN_Desc,
					RX_PK,
					RX_Code, 
					RX_Code, 
					(SELECT AdjustedCreditLimit FROM OrgAdjustedCreditLimit(OB_ARCreditLimit, OB_ARTemporaryCreditLimitIncrease, OB_ARTemporaryCreditLimitIncreaseExpiry)), 
					OJ_Code, 
					OrgBranch.GB_Code, 
					AH_ExchangeRate, 
					(CASE WHEN AH_TransactionCategory IN ('DBT','DCU','DCD','DBD') THEN 'DSB'
						ELSE
							''
					END), 
					AH_OSTotal, 
					OB_ARCategory, OB_ARConsolidatedAccountingCategory, SettleGroupOrgHeader.OH_Code,
					OrgBranch.GB_BranchName, TranBranch.GB_BranchName, SettleGroupOrgHeader.OH_FullName, RX_SubUnitRatio, AH_PostDate, GE_Code,
					AH_FullyPaidDate, 
					(CASE 
						WHEN (AH_TransactionType = 'INV' OR AH_TransactionType = 'ADJ' OR AH_TransactionType = 'CRD') THEN
							(CASE AH_InvoiceTerm
								WHEN 'COD' THEN
									'COD'
								WHEN 'PIA' THEN
									'PIA'
								WHEN 'MIC' THEN
									AH_InvoiceTerm + ' ' + CAST(AH_InvoiceTermDays AS CHAR(3)) + ' Months'
								ELSE
									AH_InvoiceTerm + ' ' + CAST(AH_InvoiceTermDays AS CHAR(3)) + ' Days'
							END)
						ELSE
							''
					END), AH_InvoiceAmount, AH_GSTAmount, JH_JobNum, AH_SystemCreateUser,
					AH_AgreedPaymentMethodOverride AS AgreedPaymentMethod,
					AH_MatchStatus,
					AH_MatchStatusReasonCode

				FROM 
					AccTransactionHeader 
					JOIN OrgHeader ON OrgHeader.OH_PK = AccTransactionHeader.AH_OH 
					JOIN GlbBranch TranBranch ON TranBranch.GB_PK = AccTransactionHeader.AH_GB
					JOIN GlbDepartment ON GlbDepartment.GE_PK = AccTransactionHeader.AH_GE
					JOIN RefCurrency ON RefCurrency.RX_Code = AccTransactionHeader.AH_RX_NKTransactionCurrency
					LEFT JOIN RefUNLOCO As ClosestPort on ClosestPort.RL_Code = OrgHeader.OH_RL_NKClosestPort
					LEFT JOIN RefCountry As Country On Country.RN_Code = ClosestPort.RL_RN_NKCountryCode
					LEFT JOIN OrgCompanyData ON OrgCompanyData.OB_OH = OrgHeader.OH_PK and OB_GC = @Company
					LEFT JOIN GlbBranch OrgBranch ON OrgBranch.GB_PK = OB_GB_ControllingBranch
					LEFT JOIN OrgDebtorGroup ON OrgDebtorGroup.OJ_PK = OrgCompanyData.OB_OJ_ARDebtorGroup
					LEFT JOIN OrgRelatedParty AS OrgRelatedPartyARSettlementGroup ON OrgRelatedPartyARSettlementGroup.PR_OH_Parent = OrgHeader.OH_PK AND OrgRelatedPartyARSettlementGroup.PR_GC = @Company AND OrgRelatedPartyARSettlementGroup.PR_PartyType = 'ARS'
					LEFT JOIN OrgHeader SettleGroupOrgHeader ON SettleGroupOrgHeader.OH_PK = OrgRelatedPartyARSettlementGroup.PR_OH_RelatedParty  
					LEFT JOIN JobHeader ON JobHeader.JH_PK = AccTransactionHeader.AH_JH
					LEFT JOIN (SELECT AP_AH, SUM(AP_Amount) TotalAP_Amount FROM AccTransactionMatchLink
								 WHERE AP_MatchDate <= @PostDateTo
								 GROUP BY AP_AH) AccTransactionMatchLink ON AccTransactionMatchLink.AP_AH = AH_PK

				WHERE AH_Ledger = @LedgerType
				AND AH_GC = @Company
				AND ((AH_PostDate >= @PostDateFrom OR @PostDateFrom = '' OR @PostDateFrom IS NULL) AND (AH_PostDate < @PostDateTo OR @PostDateTo = '' OR @PostDateTo IS NULL))
				AND ((AH_DueDate >= @DueDateFrom OR @DueDateFrom = '' OR @DueDateFrom IS NULL) AND (AH_DueDate < @DueDateTo OR @DueDateTo = '' OR @DueDateTo IS NULL))
				AND ((AH_InvoiceDate >= @InvoiceDateFrom OR @InvoiceDateFrom = '' OR @InvoiceDateFrom IS NULL) AND (AH_InvoiceDate < @InvoiceDateTo OR @InvoiceDateTo = '' OR @InvoiceDateTo IS NULL))
				AND (AH_TransactionType IN (SELECT value from SplitStringToTable(@TransactionTypeList, DEFAULT)))
				AND (OrgHeader.OH_Code IN (SELECT value from SplitStringToTable(@OrgList, DEFAULT)) OR @OrgList = '' OR @OrgList IS NULL)
				AND (TranBranch.GB_Code IN (SELECT value from SplitStringToTable(@BranchList, DEFAULT)) OR @BranchList = '' OR @BranchList IS NULL)
				AND (RN_CODE IN (SELECT value from SplitStringToTable(@CountryList, DEFAULT)) OR @CountryList = '' OR @CountryList IS NULL)
				AND (RN_CODE NOT IN (SELECT value from SplitStringToTable(@ExCountryList, DEFAULT)) OR @ExCountryList = '' OR @ExCountryList IS NULL)			
				AND (OrgBranch.GB_Code = @OrgBranch OR @OrgBranch = '' OR @OrgBranch IS NULL)
				AND (OJ_Code IN (SELECT value from SplitStringToTable(@OrgGroupList, DEFAULT)) OR @OrgGroupList = '' OR @OrgGroupList IS NULL)
				AND (OB_ARCategory IN (SELECT value from SplitStringToTable(@AccountsRelationShip, DEFAULT)) OR @AccountsRelationShip = '' OR @AccountsRelationShip IS NULL)
				AND (OB_ARConsolidatedAccountingCategory IN (SELECT value from SplitStringToTable(@ConsolidatedCategory, DEFAULT)) OR @ConsolidatedCategory = '' OR @ConsolidatedCategory IS NULL)
				AND (RX_Code IN (SELECT value from SplitStringToTable(@CurrencyList, DEFAULT)) OR @CurrencyList = '' OR @CurrencyList IS NULL)
				AND (@SettlementGroupList = '' OR @SettlementGroupList IS NULL OR 
					CASE WHEN SettleGroupOrgHeader.OH_Code IS NULL 
						THEN OrgHeader.OH_Code
						ELSE SettleGroupOrgHeader.OH_Code
					END IN (SELECT value from SplitStringToTable(@SettlementGroupList, DEFAULT)) )
				AND (OrgCompanyData.OB_ARCreditRating IN (SELECT value from SplitStringToTable(@CreditRating, DEFAULT)) OR @CreditRating = '' OR @CreditRating IS NULL)
				AND (
						isnull(@SalesRepList, '') = '' 
					OR
						OrgHeader.OH_PK IN (SELECT O8_OH 
										FROM csfn_OrgStaffAssignmentsForCompany(@Company)
										LEFT JOIN GlbStaff ON GS_Code = O8_GS_NKPersonResponsible
										WHERE O8_Department = 'ALL'									
										AND GS_Code = @SalesRepList
										AND (O8_Role IN (SELECT value from SplitStringToTable(@SalesRepRoll, DEFAULT)) OR @SalesRepRoll = '' OR @SalesRepRoll IS NULL)
										)
					)
				AND 
				(
					@ShowOnlyAggregated = ''
					 OR AH_PostToGL = @ShowOnlyAggregated
				)
				AND
				(
					AH_PK NOT IN (SELECT AOL_AH FROM AccCollectionOrderLine WHERE AOL_IsCancelled = 0) 
					OR 
					(
						-- @NotInActiveBatchTranOnly is obsolete and will be removed in future work item. Please use @IncludeActiveBatchTran instead.
						ISNULL(@NotInActiveBatchTranOnly, 'N') <> 'Y'
						AND
						ISNULL(@IncludeActiveBatchTran, '') = 'Y'
						AND 
						(
							AH_PK IN ( 
								SELECT AOL_AH FROM AccCollectionOrderLine 
								INNER JOIN AccCollectionOrder ON AccCollectionOrderLine.AOL_ACO = AccCollectionOrder.ACO_PK
								INNER JOIN AccCollectionBatch ON AccCollectionOrder.ACO_ACB = AccCollectionBatch.ACB_PK
								WHERE AccCollectionBatch.ACB_Type NOT IN (
									SELECT value FROM SplitStringToTable(ISNULL(@FilterNotActiveBatchTran, ''), ',')
								)
								AND AccCollectionOrderLine.AOL_IsCancelled = 0
							)
						)
					)
				)
				AND
				(
					ISNULL(@AgreedPaymentMethodList, '') = ''
					OR
					CASE
						WHEN AH_AgreedPaymentMethodOverride <> '' THEN AH_AgreedPaymentMethodOverride
						ELSE 'Undefined'
					END 
					IN (SELECT value FROM SplitStringToTable(@AgreedPaymentMethodList, DEFAULT))
				) OPTION(RECOMPILE);
		END
		ELSE IF @LedgerType = 'AP'
		BEGIN
			INSERT INTO #TRANSACTIONS
				(TransactionPK, AccountPK, TransactionType, TransactionTypeDesc, InvoiceRef, Description, InvoiceRef2, 
				InvoiceTotal, Balance, DueDate, InvoiceDate, AccountCode, AccountCode2, AccountName, BranchCode, CountryCode, CountryName, CurrencyPK, CurrencyCode, CurrencyCode2, CreditLimit, 
				AccountGroup, OrgBranchCode, ExchangeRate, IsDSBInvoice, OSTotal, ARCategory, ConsolidationCategory, SettlementCode, 
				OrgBranchName, TranBranchName, SettlementName, RXSubUnitRatio, PostDate, DepartmentCode, FullyPaidDate, InvoiceTerm,
				InvoiceExTax, TaxAmount, JobNumber, OperatorInitials, AgreedPaymentMethod, MatchStatus, MatchStatusReason)
		
				SELECT AH_PK, AH_OH, AH_TransactionType, 
					CASE AH_TransactionType
						WHEN 'INV' THEN 'Invoice'
						WHEN 'CRD' THEN 'Credit Notes'
						WHEN 'ADJ' THEN 'Adjustment Notes'
						WHEN 'JNL' THEN 'Journals'
						WHEN 'CTR' THEN 'Contras'
						WHEN 'TRF' THEN 'Transfers'
						WHEN 'REC' THEN 'Receipts'
						WHEN 'PAY' THEN 'Payments'
						WHEN 'EXX' THEN 'Exchanges'
						WHEN 'DSC' THEN 'Discounts'
						WHEN 'OVP' THEN 'Overpayments'
					END, AH_TransactionNum, AH_Desc, 
					AccTransactionHeader.AH_ConsolidatedInvoiceRef,
					AH_LocalTotal, 
					CASE @UseOutstandingAmount WHEN 1 THEN AH_OutstandingAmount  
						ELSE AH_LocalTotal - ISNULL(AccTransactionMatchLink.TotalAP_Amount, 0) END,
					AH_DueDate, AH_InvoiceDate, OrgHeader.OH_Code, OrgHeader.OH_Code, OrgHeader.OH_FullName, TranBranch.GB_Code, RN_CODE, RN_Desc,
					RX_PK, RX_Code, RX_Code, OB_APCreditLimit, OG_Code, OrgBranch.GB_Code, AH_ExchangeRate, 
					(CASE AH_TransactionCategory
						WHEN 'DBT' THEN
							'DSB'
						ELSE
							''
					END), AH_OSTotal, OB_APCategory, OB_ARConsolidatedAccountingCategory, SettleGroupOrgHeader.OH_Code,
					OrgBranch.GB_BranchName, TranBranch.GB_BranchName, SettleGroupOrgHeader.OH_FullName, RX_SubUnitRatio, AH_PostDate, GE_Code,
					AH_FullyPaidDate, 
					(CASE 
						WHEN (AH_TransactionType = 'INV' OR AH_TransactionType = 'ADJ' OR AH_TransactionType = 'CRD') THEN
							(CASE AH_InvoiceTerm
								WHEN 'COD' THEN
									'COD'
								WHEN 'PIA' THEN
									'PIA'
								WHEN 'MIC' THEN
									AH_InvoiceTerm + ' ' + CAST(AH_InvoiceTermDays AS CHAR(3)) + ' Months'
								ELSE
									AH_InvoiceTerm + ' ' + CAST(AH_InvoiceTermDays AS CHAR(3)) + ' Days'
							END)
						ELSE
							''
					END), AH_InvoiceAmount, AH_GSTAmount, JH_JobNum, AH_SystemCreateUser,
					AH_AgreedPaymentMethodOverride AS AgreedPaymentMethod,
					AH_MatchStatus,
					AH_MatchStatusReasonCode
				FROM AccTransactionHeader
				JOIN OrgHeader ON OrgHeader.OH_PK = AccTransactionHeader.AH_OH 
				JOIN GlbBranch TranBranch ON TranBranch.GB_PK = AccTransactionHeader.AH_GB
				JOIN GlbDepartment ON GlbDepartment.GE_PK = AccTransactionHeader.AH_GE
				JOIN RefCurrency ON RefCurrency.RX_Code = AccTransactionHeader.AH_RX_NKTransactionCurrency
				LEFT JOIN RefUNLOCO As ClosestPort on ClosestPort.RL_Code = OrgHeader.OH_RL_NKClosestPort
				LEFT JOIN RefCountry As Country On Country.RN_Code = ClosestPort.RL_RN_NKCountryCode
				LEFT JOIN OrgCompanyData ON OrgCompanyData.OB_OH = OrgHeader.OH_PK and OB_GC = @Company
				LEFT JOIN GlbBranch OrgBranch ON OrgBranch.GB_PK = OB_GB_ControllingBranch
				LEFT JOIN OrgCreditorGroup ON OrgCreditorGroup.OG_PK = OrgCompanyData.OB_OG_APCreditorGroup
				LEFT JOIN OrgRelatedParty AS OrgRelatedPartyAPSettlementGroup ON OrgRelatedPartyAPSettlementGroup.PR_OH_Parent = OrgHeader.OH_PK AND OrgRelatedPartyAPSettlementGroup.PR_GC = @Company AND OrgRelatedPartyAPSettlementGroup.PR_PartyType = 'APS'
				LEFT JOIN OrgHeader SettleGroupOrgHeader ON SettleGroupOrgHeader.OH_PK = OrgRelatedPartyAPSettlementGroup.PR_OH_RelatedParty  
				LEFT JOIN JobHeader ON JobHeader.JH_PK = AccTransactionHeader.AH_JH
				LEFT JOIN (SELECT AP_AH, SUM(AP_Amount) TotalAP_Amount FROM AccTransactionMatchLink
				   WHERE AP_MatchDate <= @PostDateTo
				   GROUP BY AP_AH) AccTransactionMatchLink ON AccTransactionMatchLink.AP_AH = AH_PK

				WHERE AH_Ledger = @LedgerType
				AND AH_GC = @Company
				AND ((AH_PostDate >= @PostDateFrom OR @PostDateFrom = '' OR @PostDateFrom IS NULL) AND (AH_PostDate < @PostDateTo OR @PostDateTo = '' OR @PostDateTo IS NULL))
				AND ((AH_DueDate >= @DueDateFrom OR @DueDateFrom = '' OR @DueDateFrom IS NULL) AND (AH_DueDate < @DueDateTo OR @DueDateTo = '' OR @DueDateTo IS NULL))
				AND ((AH_InvoiceDate >= @InvoiceDateFrom OR @InvoiceDateFrom = '' OR @InvoiceDateFrom IS NULL) AND (AH_InvoiceDate < @InvoiceDateTo OR @InvoiceDateTo = '' OR @InvoiceDateTo IS NULL))
				AND (AH_TransactionType IN (SELECT value from SplitStringToTable(@TransactionTypeList, DEFAULT)))
				AND (OrgHeader.OH_Code IN (SELECT value from SplitStringToTable(@OrgList, DEFAULT)) OR @OrgList = '' OR @OrgList IS NULL)
				AND (TranBranch.GB_Code IN (SELECT value from SplitStringToTable(@BranchList, DEFAULT)) OR @BranchList = '' OR @BranchList IS NULL)
				AND (RN_CODE IN (SELECT value from SplitStringToTable(@CountryList, DEFAULT)) OR @CountryList = '' OR @CountryList IS NULL)
				AND (RN_CODE NOT IN (SELECT value from SplitStringToTable(@ExCountryList, DEFAULT)) OR @ExCountryList = '' OR @ExCountryList IS NULL)			
				AND (OrgBranch.GB_Code = @OrgBranch OR @OrgBranch = '' OR @OrgBranch IS NULL)
				AND (OG_Code IN (SELECT value from SplitStringToTable(@OrgGroupList, DEFAULT)) OR @OrgGroupList = '' OR @OrgGroupList IS NULL)
				AND (OB_APCategory IN (SELECT value from SplitStringToTable(@AccountsRelationShip, DEFAULT)) OR @AccountsRelationShip = '' OR @AccountsRelationShip IS NULL)
				AND (OB_ARConsolidatedAccountingCategory IN (SELECT value from SplitStringToTable(@ConsolidatedCategory, DEFAULT)) OR @ConsolidatedCategory = '' OR @ConsolidatedCategory IS NULL)
				AND (RX_Code IN (SELECT value from SplitStringToTable(@CurrencyList, DEFAULT)) OR @CurrencyList = '' OR @CurrencyList IS NULL)
				AND (@SettlementGroupList = '' OR @SettlementGroupList IS NULL OR 
					CASE WHEN SettleGroupOrgHeader.OH_Code IS NULL 
						THEN OrgHeader.OH_Code
						ELSE SettleGroupOrgHeader.OH_Code 
					END IN (SELECT value from SplitStringToTable(@SettlementGroupList, DEFAULT)) )
				AND (OrgCompanyData.OB_ARCreditRating IN (SELECT value from SplitStringToTable(@CreditRating, DEFAULT)) OR @CreditRating = '' OR @CreditRating IS NULL)
				AND (
						isnull(@SalesRepList, '') = '' 
					OR
						OrgHeader.OH_PK IN (SELECT O8_OH 
										FROM csfn_OrgStaffAssignmentsForCompany(@Company)
										LEFT JOIN GlbStaff ON GS_Code = O8_GS_NKPersonResponsible
										WHERE O8_Department = 'ALL' 
										AND GS_Code = @SalesRepList
										AND (O8_Role IN (SELECT value from SplitStringToTable(@SalesRepRoll, DEFAULT)) OR @SalesRepRoll = '' OR @SalesRepRoll IS NULL)
										)
					)
				AND 
				(
					@ShowOnlyAggregated = ''
					 OR AH_PostToGL = @ShowOnlyAggregated
				)
				AND
				(
					ISNULL(@AgreedPaymentMethodList, '') = ''
					OR
					CASE
						WHEN AH_AgreedPaymentMethodOverride <> '' THEN AH_AgreedPaymentMethodOverride
						ELSE 'Undefined'
					END 
					IN (SELECT value FROM SplitStringToTable(@AgreedPaymentMethodList, DEFAULT)) 
				) OPTION(RECOMPILE);
		END
	END
	IF @PaymentStatus = 'FUL'
	BEGIN
		DELETE FROM #TRANSACTIONS WHERE Balance <> 0
	END
	ELSE IF @PaymentStatus = 'UNP'
	BEGIN
		DELETE FROM #TRANSACTIONS WHERE InvoiceTotal <> Balance OR ( InvoiceTotal = 0 AND Balance = 0 )
	END
	ELSE IF @PaymentStatus = 'PAR'
	BEGIN
		DELETE FROM #TRANSACTIONS WHERE (InvoiceTotal = Balance OR Balance = 0)
	END

END
ELSE BEGIN

	IF @ReportDate >= @Today SET @UseOutstandingAmount = 1
	IF @MatchedBranchFound = 'Y'
	BEGIN
		IF @LedgerType = 'AR'
		BEGIN

			ALTER TABLE #TRANSACTIONS ADD SettleGroupOrgHeader_OH_PK UNIQUEIDENTIFIER;
			ALTER TABLE #TRANSACTIONS ADD AH_GE UNIQUEIDENTIFIER;
			ALTER TABLE #TRANSACTIONS ADD AH_GB UNIQUEIDENTIFIER;

			INSERT INTO #TRANSACTIONS
				(TransactionPK, AccountPK, TransactionType, InvoiceRef, Description, InvoiceRef2, 
				InvoiceTotal, Balance, BalanceInLocal, DueDate, InvoiceDate, AccountCode, AccountCode2, AccountName, BranchCode, CountryCode, CountryName, CurrencyPK, CurrencyCode, CurrencyCode2, CreditLimit, 
				AccountGroup, OrgBranchCode, ExchangeRate, IsDSBInvoice, OSTotal, ARCategory, ConsolidationCategory, SettlementCode, 
				OrgBranchName, TranBranchName, SettlementName, RXSubUnitRatio, InvoiceTerm, PostDate, OperatorInitials,
				SettleGroupOrgHeader_OH_PK, AH_GE, AH_GB, AgreedPaymentMethod, MatchStatus, MatchStatusReason)

				SELECT AH_PK, AH_OH, AH_TransactionType, AH_TransactionNum, AH_Desc, 
					AccTransactionHeader.AH_ConsolidatedInvoiceRef,
					AH_LocalTotal,
					CASE @UseOutstandingAmount WHEN 1 THEN AH_OutstandingAmount  
						ELSE AH_OutstandingAmount + ISNULL(AccTransactionMatchLink.TotalAP_Amount, 0) END,
					CASE @UseOutstandingAmount WHEN 1 THEN AH_OutstandingAmount  
						ELSE AH_OutstandingAmount + ISNULL(AccTransactionMatchLink.TotalAP_Amount, 0) END,
					AH_DueDate, AH_InvoiceDate, OrgHeader.OH_Code, OrgHeader.OH_Code, OrgHeader.OH_FullName, TranBranch.GB_Code, RN_CODE, RN_Desc,
					RX_PK, RX_Code, RX_Code,				
					(SELECT AdjustedCreditLimit FROM OrgAdjustedCreditLimit(OrgCompanyData.OB_ARCreditLimit, OrgCompanyData.OB_ARTemporaryCreditLimitIncrease, OrgCompanyData.OB_ARTemporaryCreditLimitIncreaseExpiry)), 
					OJ_Code, OrgBranch.GB_Code, AH_ExchangeRate, 
							(CASE WHEN AH_TransactionCategory IN ('DBT','DCU','DCD','DBD') THEN 'DSB'
								ELSE
									''
							END), AH_OSTotal, OrgCompanyData.OB_ARCategory, OrgCompanyData.OB_ARConsolidatedAccountingCategory, SettleGroupOrgHeader.OH_Code,
					OrgBranch.GB_BranchName, TranBranch.GB_BranchName, SettleGroupOrgHeader.OH_FullName, RX_SubUnitRatio,
					(CASE WHEN OrgCompanyData.OB_ARCreditApproved = 0 OR OrgCompanyData.OB_AROnCreditHold = 1 
							THEN 'COD' 
							ELSE '' /*to be updated later*/
					 END) AS InvoiceTerm,	 						
					AH_PostDate,
					AH_SystemCreateUser,
					SettleGroupOrgHeader.OH_PK, AH_GE, AH_GB,
					AH_AgreedPaymentMethodOverride AS AgreedPaymentMethod,
					AH_MatchStatus,
					AH_MatchStatusReasonCode
				FROM AccTransactionHeader
				LEFT JOIN (SELECT AP_AH, SUM(AP_Amount) TotalAP_Amount FROM AccTransactionMatchLink
						   WHERE AP_MatchDate > @ReportDate
						   GROUP BY AP_AH) AccTransactionMatchLink ON AccTransactionMatchLink.AP_AH = AH_PK
				LEFT JOIN OrgHeader ON OrgHeader.OH_PK = AccTransactionHeader.AH_OH 
				LEFT JOIN GlbBranch TranBranch ON TranBranch.GB_PK = AccTransactionHeader.AH_GB
				LEFT JOIN GlbDepartment ON GlbDepartment.GE_PK = AccTransactionHeader.AH_GE
				LEFT JOIN RefCurrency ON RefCurrency.RX_Code = AccTransactionHeader.AH_RX_NKTransactionCurrency
				LEFT JOIN RefUNLOCO As ClosestPort on ClosestPort.RL_Code = OrgHeader.OH_RL_NKClosestPort
				LEFT JOIN RefCountry As Country On Country.RN_Code = ClosestPort.RL_RN_NKCountryCode
				LEFT JOIN OrgCompanyData  ON OrgCompanyData.OB_OH = OrgHeader.OH_PK and OrgCompanyData.OB_GC = @Company				
				LEFT JOIN GlbBranch OrgBranch ON OrgBranch.GB_PK = OB_GB_ControllingBranch
				LEFT JOIN OrgDebtorGroup ON OrgDebtorGroup.OJ_PK = OrgCompanyData.OB_OJ_ARDebtorGroup
				LEFT JOIN OrgRelatedParty AS OrgRelatedPartyARSettlementGroup ON OrgRelatedPartyARSettlementGroup.PR_OH_Parent = OrgHeader.OH_PK AND OrgRelatedPartyARSettlementGroup.PR_GC = @Company AND OrgRelatedPartyARSettlementGroup.PR_PartyType = 'ARS'
				LEFT JOIN OrgHeader SettleGroupOrgHeader ON SettleGroupOrgHeader.OH_PK = OrgRelatedPartyARSettlementGroup.PR_OH_RelatedParty  
				WHERE AH_GC = @Company
				AND AH_Ledger = @LedgerType
				AND AH_TransactionType != 'INB'
				AND (AH_FullyPaidDate > @ReportDate OR AH_FullyPaidDate IS NULL)
				AND AH_PostDate <= @ReportDate
				AND CASE WHEN @FutureRECPAYNotInBalance = 'Y' THEN 1
					ELSE
						CASE @UseOutstandingAmount WHEN 1 THEN AH_OutstandingAmount  
						ELSE AH_OutstandingAmount + ISNULL(AccTransactionMatchLink.TotalAP_Amount, 0) END
					END != 0
				AND (@OrgList = '' OR @OrgList IS NULL OR OrgHeader.OH_Code IN (SELECT value from SplitStringToTable(@OrgList, DEFAULT)))
				AND (@BranchList = '' OR @BranchList IS NULL OR TranBranch.GB_Code IN (SELECT value from SplitStringToTable(@BranchList, DEFAULT)))
				AND (@CountryList = '' OR @CountryList IS NULL OR RN_CODE IN (SELECT value from SplitStringToTable(@CountryList, DEFAULT)))
				AND (@ExCountryList = '' OR @ExCountryList IS NULL OR RN_CODE NOT IN (SELECT value from SplitStringToTable(@ExCountryList, DEFAULT)))			
				AND (@OrgBranch = '' OR @OrgBranch IS NULL OR OrgBranch.GB_Code = @OrgBranch)
				AND (@OrgGroupList = '' OR @OrgGroupList IS NULL OR OJ_Code IN (SELECT value from SplitStringToTable(@OrgGroupList, DEFAULT)))
				AND (@AccountsRelationShip = '' OR @AccountsRelationShip IS NULL OR OrgCompanyData.OB_ARCategory IN (SELECT value from SplitStringToTable(@AccountsRelationShip, DEFAULT)))
				AND (@ConsolidatedCategory = '' OR @ConsolidatedCategory IS NULL OR OrgCompanyData.OB_ARConsolidatedAccountingCategory IN (SELECT value from SplitStringToTable(@ConsolidatedCategory, DEFAULT)))
				AND (@CurrencyList = '' OR @CurrencyList IS NULL OR RX_Code IN (SELECT value from SplitStringToTable(@CurrencyList, DEFAULT)))
				AND (@SettlementGroupList = '' OR @SettlementGroupList IS NULL OR 
					CASE WHEN SettleGroupOrgHeader.OH_Code IS NULL 
						THEN OrgHeader.OH_Code
						ELSE SettleGroupOrgHeader.OH_Code
					END IN (SELECT value from SplitStringToTable(@SettlementGroupList, DEFAULT)) )
				AND (@CreditRating = '' OR @CreditRating IS NULL OR OrgCompanyData.OB_ARCreditRating IN (SELECT value from SplitStringToTable(@CreditRating, DEFAULT)))
				AND (
					isnull(@SalesRepList, '') = '' 
					OR
					OrgHeader.OH_PK IN (SELECT O8_OH 
										FROM csfn_OrgStaffAssignmentsForCompany(@Company)
										LEFT JOIN GlbStaff ON GS_Code = O8_GS_NKPersonResponsible
										WHERE O8_Department = 'ALL'							
										AND GS_Code = @SalesRepList
										AND (@SalesRepRoll = '' OR @SalesRepRoll IS NULL OR O8_Role IN (SELECT value from SplitStringToTable(@SalesRepRoll, DEFAULT)))
										)
					)
				AND 
				(
					@ShowOnlyAggregated = ''
					OR AH_PostToGL = @ShowOnlyAggregated
				)
				AND 
				(
					AH_PK NOT IN (SELECT AOL_AH FROM AccCollectionOrderLine WHERE AOL_IsCancelled = 0) 
					OR 
					(
						-- @NotInActiveBatchTranOnly is obsolete and will be removed in future work item. Please use @IncludeActiveBatchTran instead.
						ISNULL(@NotInActiveBatchTranOnly, 'N') <> 'Y'
						AND
						ISNULL(@IncludeActiveBatchTran, '') = 'Y'
						AND 
						(
							AH_PK IN ( 
								SELECT AOL_AH FROM AccCollectionOrderLine 
								INNER JOIN AccCollectionOrder ON AccCollectionOrderLine.AOL_ACO = AccCollectionOrder.ACO_PK
								INNER JOIN AccCollectionBatch ON AccCollectionOrder.ACO_ACB = AccCollectionBatch.ACB_PK
								WHERE AccCollectionBatch.ACB_GC = @Company
								AND AccCollectionBatch.ACB_Type NOT IN (
									SELECT value FROM SplitStringToTable(ISNULL(@FilterNotActiveBatchTran, ''), ',')
								)
								AND AccCollectionOrderLine.AOL_IsCancelled = 0
							)
						)
					)
				)
				AND
				(
					ISNULL(@AgreedPaymentMethodList, '') = ''
					OR
					CASE
						WHEN AH_AgreedPaymentMethodOverride <> '' THEN AH_AgreedPaymentMethodOverride
						ELSE 'Undefined'
					END 
					IN (SELECT value FROM SplitStringToTable(@AgreedPaymentMethodList, DEFAULT))
				) OPTION(RECOMPILE);

				UPDATE TX /*STEP 1*/
				   SET InvoiceTerm = 
						CASE(ISNULL(MatchedARTerms.PY_InvoiceTerm, '')) 
							WHEN  'DEF' THEN  
								'' --update via step 2
							WHEN 'COD' THEN   
								'COD'  
							WHEN 'PIA' THEN   
								'PIA'  
							WHEN 'MIC' THEN   
								CAST(ISNULL(MatchedARTerms.PY_InvoiceDays, '') AS VARCHAR(3)) + ' Months ' + ISNULL(MatchedARTerms.PY_InvoiceTerm, '')  
							ELSE    
								CAST(ISNULL(MatchedARTerms.PY_InvoiceDays, '') AS VARCHAR(3)) + ' Days '   + ISNULL(MatchedARTerms.PY_InvoiceTerm, '')  
						 END 
				FROM #TRANSACTIONS TX
				OUTER APPLY dbo.[GetBestMatchedOrgARTerms](@Company, TX.AccountPK,  'ALL', 'ALL', 'ALL', TX.AH_GE, TX.AH_GB, 'ALL')  AS MatchedARTerms
				WHERE TX.InvoiceTerm = ''
				OPTION(RECOMPILE);
				
				UPDATE TX /*STEP 2*/
				   SET InvoiceTerm = 
						CASE ISNULL(SettleGroupMatchedARTerms.PY_InvoiceTerm, '')  
							WHEN 'COD' THEN   
								'COD'  
							WHEN 'PIA' THEN   
								'PIA'  
							WHEN 'MIC' THEN   
								CAST(ISNULL(SettleGroupMatchedARTerms.PY_InvoiceDays, '') AS VARCHAR(3)) + ' Months ' + ISNULL(SettleGroupMatchedARTerms.PY_InvoiceTerm, '')  
							ELSE    
								CAST(ISNULL(SettleGroupMatchedARTerms.PY_InvoiceDays, '') AS VARCHAR(3)) + ' Days '   + ISNULL(SettleGroupMatchedARTerms.PY_InvoiceTerm, '')  
						END  					
				FROM #TRANSACTIONS TX
				OUTER APPLY dbo.GetBestMatchedOrgARTerms(@Company, TX.SettleGroupOrgHeader_OH_PK, 'ALL', 'ALL', 'ALL', TX.AH_GE, TX.AH_GB, 'ALL') AS SettleGroupMatchedARTerms
				WHERE InvoiceTerm = ''
				OPTION(RECOMPILE);
				
				ALTER TABLE #TRANSACTIONS DROP COLUMN SettleGroupOrgHeader_OH_PK;
				ALTER TABLE #TRANSACTIONS DROP COLUMN AH_GE;
				ALTER TABLE #TRANSACTIONS DROP COLUMN AH_GB;
		END
		ELSE IF @LedgerType = 'AP'
		BEGIN

			INSERT INTO #TRANSACTIONS
				(TransactionPK, AccountPK, TransactionType, InvoiceRef, Description, InvoiceRef2, 
				InvoiceTotal, Balance, BalanceInLocal, DueDate, InvoiceDate, AccountCode, AccountCode2, AccountName, BranchCode, CountryCode, CountryName, CurrencyPK, CurrencyCode, CurrencyCode2, CreditLimit, 
				AccountGroup, OrgBranchCode, ExchangeRate, IsDSBInvoice, OSTotal, ARCategory, ConsolidationCategory, SettlementCode, 
				OrgBranchName, TranBranchName, SettlementName, RXSubUnitRatio, PostDate, OperatorInitials, AgreedPaymentMethod, MatchStatus, MatchStatusReason)

				SELECT AH_PK, AH_OH, AH_TransactionType, AH_TransactionNum, AH_Desc, 
					AccTransactionHeader.AH_ConsolidatedInvoiceRef,
					AH_LocalTotal, 
					CASE @UseOutstandingAmount WHEN 1 THEN AH_OutstandingAmount  
						ELSE AH_OutstandingAmount + ISNULL(AccTransactionMatchLink.TotalAP_Amount, 0) END,
					CASE @UseOutstandingAmount WHEN 1 THEN AH_OutstandingAmount  
						ELSE AH_OutstandingAmount + ISNULL(AccTransactionMatchLink.TotalAP_Amount, 0) END,
					AH_DueDate, AH_InvoiceDate, OrgHeader.OH_Code, OrgHeader.OH_Code, OrgHeader.OH_FullName, TranBranch.GB_Code, RN_CODE, RN_Desc,
					RX_PK, RX_Code, RX_Code, OB_APCreditLimit, OG_Code, OrgBranch.GB_Code, AH_ExchangeRate,
					'' , AH_OSTotal, OB_APCategory, OB_ARConsolidatedAccountingCategory, SettleGroupOrgHeader.OH_Code,
					OrgBranch.GB_BranchName, TranBranch.GB_BranchName, SettleGroupOrgHeader.OH_FullName, RX_SubUnitRatio, AH_PostDate, AH_SystemCreateUser,
					AH_AgreedPaymentMethodOverride AS AgreedPaymentMethod,
					AH_MatchStatus,
					AH_MatchStatusReasonCode

				FROM AccTransactionHeader 
				LEFT JOIN (SELECT AP_AH, SUM(AP_Amount) TotalAP_Amount FROM AccTransactionMatchLink
						   WHERE AP_MatchDate > @ReportDate
						   GROUP BY AP_AH) AccTransactionMatchLink ON AccTransactionMatchLink.AP_AH = AH_PK
				LEFT JOIN OrgHeader ON OrgHeader.OH_PK = AccTransactionHeader.AH_OH 
				LEFT JOIN GlbBranch TranBranch ON TranBranch.GB_PK = AccTransactionHeader.AH_GB
				LEFT JOIN GlbDepartment ON GlbDepartment.GE_PK = AccTransactionHeader.AH_GE
				LEFT JOIN RefCurrency ON RefCurrency.RX_Code = AccTransactionHeader.AH_RX_NKTransactionCurrency
				LEFT JOIN RefUNLOCO As ClosestPort on ClosestPort.RL_Code = OrgHeader.OH_RL_NKClosestPort
				LEFT JOIN RefCountry As Country On Country.RN_Code = ClosestPort.RL_RN_NKCountryCode
				LEFT JOIN OrgCompanyData ON OrgCompanyData.OB_OH = OrgHeader.OH_PK and OB_GC = @Company
				LEFT JOIN GlbBranch OrgBranch ON OrgBranch.GB_PK = OB_GB_ControllingBranch
				LEFT JOIN OrgCreditorGroup ON OrgCreditorGroup.OG_PK = OrgCompanyData.OB_OG_APCreditorGroup
				LEFT JOIN OrgRelatedParty AS OrgRelatedPartyAPSettlementGroup ON OrgRelatedPartyAPSettlementGroup.PR_OH_Parent = OrgHeader.OH_PK AND OrgRelatedPartyAPSettlementGroup.PR_GC = @Company AND OrgRelatedPartyAPSettlementGroup.PR_PartyType = 'APS'
				LEFT JOIN OrgHeader SettleGroupOrgHeader ON SettleGroupOrgHeader.OH_PK = OrgRelatedPartyAPSettlementGroup.PR_OH_RelatedParty  
				WHERE AH_GC = @Company
				AND AH_Ledger = @LedgerType
				AND AH_TransactionType != 'INB'
				AND (AH_FullyPaidDate > @ReportDate OR AH_FullyPaidDate IS NULL)
				AND AH_PostDate <= @ReportDate
				AND CASE WHEN @FutureRECPAYNotInBalance = 'Y' THEN 1
					ELSE
						CASE @UseOutstandingAmount WHEN 1 THEN AH_OutstandingAmount  
						ELSE AH_OutstandingAmount + ISNULL(AccTransactionMatchLink.TotalAP_Amount, 0) END
					END != 0
				AND (@OrgList = '' OR @OrgList IS NULL OR OrgHeader.OH_Code IN (SELECT value from SplitStringToTable(@OrgList, DEFAULT)))
				AND (@BranchList = '' OR @BranchList IS NULL OR TranBranch.GB_Code IN (SELECT value from SplitStringToTable(@BranchList, DEFAULT)))
				AND (@CountryList = '' OR @CountryList IS NULL OR RN_CODE IN (SELECT value from SplitStringToTable(@CountryList, DEFAULT)))
				AND (@ExCountryList = '' OR @ExCountryList IS NULL OR RN_CODE NOT IN (SELECT value from SplitStringToTable(@ExCountryList, DEFAULT)))			
				AND (@OrgBranch = '' OR @OrgBranch IS NULL OR OrgBranch.GB_Code = @OrgBranch)
				AND (@OrgGroupList = '' OR @OrgGroupList IS NULL OR OG_Code IN (SELECT value from SplitStringToTable(@OrgGroupList, DEFAULT)))
				AND (@AccountsRelationShip = '' OR @AccountsRelationShip IS NULL OR OB_APCategory IN (SELECT value from SplitStringToTable(@AccountsRelationShip, DEFAULT)))
				AND (@ConsolidatedCategory = '' OR @ConsolidatedCategory IS NULL OR OB_ARConsolidatedAccountingCategory IN (SELECT value from SplitStringToTable(@ConsolidatedCategory, DEFAULT)))
				AND (@CurrencyList = '' OR @CurrencyList IS NULL OR RX_Code IN (SELECT value from SplitStringToTable(@CurrencyList, DEFAULT)))
				AND (@SettlementGroupList = '' OR @SettlementGroupList IS NULL OR 
					CASE WHEN SettleGroupOrgHeader.OH_Code IS NULL 
						THEN OrgHeader.OH_Code
						ELSE SettleGroupOrgHeader.OH_Code 
					END IN (SELECT value from SplitStringToTable(@SettlementGroupList, DEFAULT)) )
				AND (
					isnull(@SalesRepList, '') = '' 
					OR
					OrgHeader.OH_PK IN (SELECT O8_OH 
										FROM csfn_OrgStaffAssignmentsForCompany(@Company)
										LEFT JOIN GlbStaff ON GS_Code = O8_GS_NKPersonResponsible
										WHERE O8_Department = 'ALL'							
										AND GS_Code = @SalesRepList
										AND (@SalesRepRoll = '' OR @SalesRepRoll IS NULL OR O8_Role IN (SELECT value from SplitStringToTable(@SalesRepRoll, DEFAULT)))
										)
					)
				AND 
				(
					@ShowOnlyAggregated = ''
					 OR AH_PostToGL = @ShowOnlyAggregated
				)
				AND
				(
					ISNULL(@AgreedPaymentMethodList, '') = ''
					OR
					CASE
						WHEN AH_AgreedPaymentMethodOverride <> '' THEN AH_AgreedPaymentMethodOverride
						ELSE 'Undefined'
					END 
					IN (SELECT value FROM SplitStringToTable(@AgreedPaymentMethodList, DEFAULT))
				) OPTION(RECOMPILE);
		END
	END
END
--------------------------------------------------------------------------------------------
-- UPDATE Transactions Matched To Future REC/PAY
--------------------------------------------------------------------------------------------
IF @FutureRECPAYNotInBalance = 'Y'
BEGIN
	UPDATE #TRANSACTIONS 
		SET MatchedInFuturePeriodInLocalCurrency = (
			SELECT ISNULL(SUM(AP_Amount), 0) 
			FROM AccTransactionMatchLink
			WHERE AP_AH = TransactionPK 
			AND AP_MatchGroupNum IN (
				SELECT AP_MatchGroupNum 
				FROM AccTransactionMatchLink
					LEFT JOIN AccTransactionHeader ON AP_AH = AH_PK
				WHERE AH_TransactionType IN ('PAY','REC') 
					AND AH_PostDate > @ReportDate
					AND AH_GC = @Company
				)
			)
	OPTION(RECOMPILE);

	UPDATE #TRANSACTIONS SET MatchedInFuturePeriodInInvoiceCurrency = MatchedInFuturePeriodInLocalCurrency

	IF @ExcludeMatchedToFutureRECPAY = 'Y'
	BEGIN
		UPDATE #TRANSACTIONS SET Balance =	CASE
												WHEN @UseOutstandingAmount != 1 THEN Balance - MatchedInFuturePeriodInLocalCurrency
												ELSE Balance
											END,
								 BalanceInLocal = CASE
												WHEN @UseOutstandingAmount != 1 THEN BalanceInLocal - MatchedInFuturePeriodInLocalCurrency
												ELSE BalanceInLocal
											END
	END
	ELSE
	BEGIN
		UPDATE #TRANSACTIONS SET Balance =	CASE
												WHEN @UseOutstandingAmount = 1 THEN Balance + MatchedInFuturePeriodInLocalCurrency
												ELSE Balance
											END,
								 BalanceInLocal  = CASE 
												WHEN @UseOutstandingAmount = 1 THEN BalanceInLocal + MatchedInFuturePeriodInLocalCurrency
												ELSE BalanceInLocal
											END
	END

	IF @SummaryOnly != 'Y'
	BEGIN
		DELETE FROM #TRANSACTIONS WHERE Balance = 0
	END
END

--------------------------------------------------------------------------------------------
-- AP Ledger Type
--------------------------------------------------------------------------------------------
IF @LedgerType = 'AP'
BEGIN
	UPDATE #TRANSACTIONS SET Balance = Balance * -1, BalanceInLocal = BalanceInLocal * -1, InvoiceTotal = InvoiceTotal * -1, 
		OSTotal = OSTotal * -1, InvoiceExTax = InvoiceExTax * -1, TaxAmount = TaxAmount * -1, MatchedInFuturePeriodInLocalCurrency = MatchedInFuturePeriodInLocalCurrency * -1 ,
		MatchedInFuturePeriodInInvoiceCurrency = MatchedInFuturePeriodInInvoiceCurrency * -1
END


--------------------------------------------------------------------------------------------
-- ShowInInvoicedCurrency
--------------------------------------------------------------------------------------------
IF @ShowInInvoicedCurrency = 'Y'
BEGIN
	IF @IsReciprocal = 1
	BEGIN
		--UPDATE #TRANSACTIONS SET Balance = Balance / ExchangeRate WHERE ExchangeRate <> 1 AND ExchangeRate <> 0 AND InvoiceTotal <> Balance
		UPDATE #TRANSACTIONS SET Balance = ROUND(Balance / ExchangeRate, LEN(RXSubUnitRatio) - 1) WHERE ExchangeRate <> 1 AND ExchangeRate <> 0 AND InvoiceTotal <> Balance
		UPDATE #TRANSACTIONS SET MatchedInFuturePeriodInInvoiceCurrency = ROUND(MatchedInFuturePeriodInInvoiceCurrency / ExchangeRate, LEN(RXSubUnitRatio) - 1) WHERE ExchangeRate <> 1 AND ExchangeRate <> 0
	END
	ELSE
	BEGIN
		--UPDATE #TRANSACTIONS SET Balance = Balance * ExchangeRate WHERE ExchangeRate <> 1 AND InvoiceTotal <> Balance
		UPDATE #TRANSACTIONS SET Balance = ROUND(Balance * ExchangeRate, LEN(RXSubUnitRatio) - 1) WHERE ExchangeRate <> 1 AND InvoiceTotal <> Balance
		UPDATE #TRANSACTIONS SET MatchedInFuturePeriodInInvoiceCurrency = ROUND(MatchedInFuturePeriodInInvoiceCurrency * ExchangeRate, LEN(RXSubUnitRatio) - 1) WHERE ExchangeRate <> 1 AND ExchangeRate <> 0
	END

	UPDATE #TRANSACTIONS SET Balance = OSTotal WHERE ExchangeRate <> 1 AND InvoiceTotal = Balance
END

--------------------------------------------------------------------------------------------
-- REMOVE Within Credit Limit
--------------------------------------------------------------------------------------------
IF @OverLimitOnly <> 'Y'
BEGIN
	UPDATE #TRANSACTIONS SET IsOverLimit = '*' WHERE AccountCode
		IN (SELECT AccountCode FROM #TRANSACTIONS GROUP BY AccountCode, CreditLimit HAVING SUM(Balance) > CreditLimit)
END

IF @LedgerType = 'AR'
BEGIN
	--------------------------------------------------------------------------------------------
	-- UDPATE Disbursement
	--------------------------------------------------------------------------------------------
	UPDATE #TRANSACTIONS SET DSBCharge = Balance WHERE IsDSBInvoice = 'DSB'
	
	--------------------------------------------------------------------------------------------
	-- Remove Non-Disbursement Transactions
	--------------------------------------------------------------------------------------------
	IF @DisbursementTranOnly = 'Y'
	BEGIN
		DELETE FROM #TRANSACTIONS WHERE DSBCharge IS NULL OR DSBCharge = 0
	END
END

--------------------------------------------------------------------------------------------
-- UPDATE Blank Settlement Code & Name
--------------------------------------------------------------------------------------------
UPDATE #TRANSACTIONS SET SettlementCode = AccountCode, SettlementName = AccountName WHERE SettlementCode = '' OR SettlementCode IS NULL;

--------------------------------------------------------------------------------------------
-- UDPATE SalesRep, CreditController, CustomerService
--------------------------------------------------------------------------------------------
WITH AssignedStaff AS
(
	SELECT O8_Role,O8_OH,O8_GS_NKPersonResponsible, GS_FullName
	FROM (
		SELECT O8_Role, O8_OH, O8_GS_NKPersonResponsible, 
			   ROW_NUMBER() OVER(PARTITION BY O8_Role, O8_OH ORDER BY O8_GS_NKPersonResponsible ASC) AS Rank1
		FROM (
				SELECT O8_Role,O8_OH,O8_GS_NKPersonResponsible 
				FROM csfn_OrgStaffAssignmentsForCompany(@Company) 
				WHERE O8_Department = 'ALL' AND O8_Role IN ('SAL','CRE','CUS')
			  ) Tb1
		) Tb2
	INNER JOIN GlbStaff on GS_Code = O8_GS_NKPersonResponsible
	WHERE Rank1 = 1
)
UPDATE TX
SET
	SalesRep = SAL.O8_GS_NKPersonResponsible,
	SalesRepName = SAL.GS_FullName,
	CreditController = CRE.O8_GS_NKPersonResponsible,
	CreditControllerName = CRE.GS_FullName,
	CustomerService = CUS.O8_GS_NKPersonResponsible,
	CustomerServiceName = CUS.GS_FullName
FROM #TRANSACTIONS TX
LEFT JOIN AssignedStaff SAL ON TX.AccountPK = SAL.O8_OH AND SAL.O8_Role = 'SAL'
LEFT JOIN AssignedStaff CRE ON TX.AccountPK = CRE.O8_OH AND CRE.O8_Role = 'CRE'
LEFT JOIN AssignedStaff CUS ON TX.AccountPK = CUS.O8_OH AND CUS.O8_Role = 'CUS';

--------------------------------------------------------------------------------------------
-- UDPATE AdditionalCompanyName
--------------------------------------------------------------------------------------------

UPDATE #TRANSACTIONS SET AdditionalCompanyName = (SELECT CompanyName FROM dbo.GetAdditionalCompanyName(AccountPK, @Company, @Branch, @LedgerType))

--------------------------------------------------------------------------------------------
-- UDPATE ContactName, ContactPhoneNo
--------------------------------------------------------------------------------------------
IF @LedgerType = 'AR'
BEGIN
UPDATE #TRANSACTIONS SET ContactName = (
    SELECT TOP 1 OC_ContactName
	FROM OrgContact LEFT JOIN OrgDocument ON OrgDocument.OD_OC = OrgContact.OC_PK
	WHERE OC_OH = #TRANSACTIONS.AccountPK AND OC_IsActive = 1 AND OD_DocumentGroup IN ('A/R', 'ALL') 
    ORDER BY OD_DocumentGroup, OD_DefaultContact DESC, OC_ContactName )
END
ELSE IF @LedgerType = 'AP'
BEGIN
UPDATE #TRANSACTIONS SET ContactName = (
    SELECT TOP 1 OC_ContactName
	FROM OrgContact LEFT JOIN OrgDocument ON OrgDocument.OD_OC = OrgContact.OC_PK
	WHERE OC_OH = #TRANSACTIONS.AccountPK AND OC_IsActive = 1 AND OD_DocumentGroup IN ('A/P', 'ALL') 
    ORDER BY OD_DocumentGroup, OD_DefaultContact DESC, OC_ContactName )
END

UPDATE #TRANSACTIONS SET OC_OH_AddressOverride = (
    SELECT OC_OH_AddressOverride
	FROM OrgContact 
    WHERE OC_OH = #TRANSACTIONS.AccountPK AND OC_ContactName = ContactName)
			
UPDATE #TRANSACTIONS SET ContactPhoneNo = (
    SELECT OC_Phone 
	FROM OrgContact
	WHERE OC_ContactName IS NOT NULL 
    AND OC_OH_AddressOverride IS NULL 
    AND OC_OH = #TRANSACTIONS.AccountPK 
    AND OC_ContactName = #TRANSACTIONS.ContactName)
WHERE #TRANSACTIONS.OC_OH_AddressOverride IS NULL

UPDATE 
	#TRANSACTIONS 
SET 
	ContactPhoneNo = OA_Phone     
FROM
	#TRANSACTIONS      
	INNER JOIN 
	(
		SELECT
			OA_OH
			,MAX(OA_Phone) AS OA_Phone
			,COUNT(*) AS MainOfficesCount
		FROM
			OrgAddress
			INNER JOIN OrgAddressCapability
			ON 
				OA_PK  = PZ_OA AND
				PZ_IsMainAddress = 1 AND
				PZ_AddressType = 'OFC'
		GROUP BY 
			OA_OH
	) MainOffice
		ON
		OA_OH = #TRANSACTIONS.OC_OH_AddressOverride
		AND MainOfficesCount = 1
WHERE 
	#TRANSACTIONS.OC_OH_AddressOverride IS NOT NULL 
	
UPDATE 
	#TRANSACTIONS 
SET 
	ContactPhoneNo = OA_Phone     
FROM
	#TRANSACTIONS      
	INNER JOIN 
	(
		SELECT TOP 1
			OA_OH,
			OA_Phone
		FROM
			OrgAddress
			INNER JOIN OrgAddressCapability
			ON 
				OA_PK  = PZ_OA AND
				PZ_IsMainAddress = 1 AND
				PZ_AddressType = 'OFC' AND 
				LEFT(OA_RL_NKRelatedPortCode,2) = @CountryCode
	) MainOffice
		ON
		OA_OH = #TRANSACTIONS.OC_OH_AddressOverride
WHERE 
	#TRANSACTIONS.OC_OH_AddressOverride IS NOT NULL 
	
	
UPDATE 
	#TRANSACTIONS 
SET 
	ContactPhoneNo = OA_Phone     
FROM
	#TRANSACTIONS      
	INNER JOIN 
	(
		SELECT
			OA_OH
			,MAX(OA_Phone) AS OA_Phone
			,COUNT(*) AS MainOfficesCount
		FROM
			OrgAddress
			INNER JOIN OrgAddressCapability 
			ON 
				OA_PK  = PZ_OA AND
				PZ_IsMainAddress = 1 AND
				PZ_AddressType = 'OFC'
		GROUP BY 
			OA_OH
	) MainOffice
		ON
		MainOffice.OA_OH = AccountPK 
		AND	MainOfficesCount = 1 

WHERE 
	ContactPhoneNo IS NULL OR ContactPhoneNo = ''  	
	
UPDATE 
	#TRANSACTIONS 
SET 
	ContactPhoneNo = OA_Phone     
FROM
	#TRANSACTIONS      
	INNER JOIN 
	(
		SELECT TOP 1
			OA_OH,
			OA_Phone
		FROM
			OrgAddress
			INNER JOIN OrgAddressCapability 
			ON 
				OA_PK  = PZ_OA AND
				PZ_IsMainAddress = 1 AND
				PZ_AddressType = 'OFC' AND 
				LEFT(OA_RL_NKRelatedPortCode,2) = @CountryCode
	) MainOffice
		ON
		MainOffice.OA_OH = AccountPK 
WHERE 
	ContactPhoneNo IS NULL OR ContactPhoneNo = ''

--------------------------------------------------------------------------------------------
-- UDPATE ContactInfo
--------------------------------------------------------------------------------------------
UPDATE #TRANSACTIONS SET ContactInfo = ISNULL(ContactName, 'No Contact Available') + ' ' + '(Ph:' + ContactPhoneNo + ')'

--------------------------------------------------------------------------------------------
-- UPDATE Period Totals by Ageing Option
--------------------------------------------------------------------------------------------
IF @AgedByInvoiceDate = 'DUE'
BEGIN
	IF @ShowLocalEquivalentTotal = 'Y'
	BEGIN
		UPDATE #TRANSACTIONS SET
			PeriodCurrent = (SELECT Balance WHERE DueDate IS NULL OR ((DueDate >= @PCurrentStart OR @P1Start IS NULL) AND (DueDate < @P1PlusStart OR @P1PlusStart IS NULL))),
			Period1Total = (SELECT Balance WHERE @P1Start IS NOT NULL AND (DueDate >= @P1Start OR @P2Start IS NULL) AND DueDate < @PCurrentStart),
			Period2Total = (SELECT Balance WHERE @P2Start IS NOT NULL AND (DueDate >= @P2Start OR @P3Start IS NULL) AND DueDate < @P1Start),
			Period3Total = (SELECT Balance WHERE @P3Start IS NOT NULL AND (DueDate >= @P3Start OR @P4Start IS NULL) AND DueDate < @P2Start),
			Period4Total = (SELECT Balance WHERE @P4Start IS NOT NULL AND DueDate < @P3Start),
			NotDue1Total = (SELECT Balance WHERE DueDate >= @P1PlusStart AND (DueDate < @P2PlusStart OR @P2PlusStart IS NULL)),
			NotDue2Total = (SELECT Balance WHERE DueDate >= @P2PlusStart AND (DueDate < @P3PlusStart OR @P3PlusStart IS NULL)),
			NotDue3Total = (SELECT Balance WHERE DueDate >= @P3PlusStart),
			PeriodCurrentInLocal = (SELECT BalanceInLocal WHERE DueDate IS NULL OR ((DueDate >= @PCurrentStart OR @P1Start IS NULL) AND (DueDate < @P1PlusStart OR @P1PlusStart IS NULL))),
			Period1TotalInLocal = (SELECT BalanceInLocal WHERE @P1Start IS NOT NULL AND (DueDate >= @P1Start OR @P2Start IS NULL) AND DueDate < @PCurrentStart),
			Period2TotalInLocal = (SELECT BalanceInLocal WHERE @P2Start IS NOT NULL AND (DueDate >= @P2Start OR @P3Start IS NULL) AND DueDate < @P1Start),
			Period3TotalInLocal = (SELECT BalanceInLocal WHERE @P3Start IS NOT NULL AND (DueDate >= @P3Start OR @P4Start IS NULL) AND DueDate < @P2Start),
			Period4TotalInLocal = (SELECT BalanceInLocal WHERE @P4Start IS NOT NULL AND DueDate < @P3Start),
			NotDue1TotalInLocal = (SELECT BalanceInLocal WHERE DueDate >= @P1PlusStart AND (DueDate < @P2PlusStart OR @P2PlusStart IS NULL)),
			NotDue2TotalInLocal = (SELECT BalanceInLocal WHERE DueDate >= @P2PlusStart AND (DueDate < @P3PlusStart OR @P3PlusStart IS NULL)),
			NotDue3TotalInLocal = (SELECT BalanceInLocal WHERE DueDate >= @P3PlusStart)
	END
	ELSE
	BEGIN
		UPDATE #TRANSACTIONS SET
			PeriodCurrent = (SELECT Balance WHERE DueDate IS NULL OR ((DueDate >= @PCurrentStart OR @P1Start IS NULL) AND (DueDate < @P1PlusStart OR @P1PlusStart IS NULL))),
			Period1Total = (SELECT Balance WHERE @P1Start IS NOT NULL AND (DueDate >= @P1Start OR @P2Start IS NULL) AND DueDate < @PCurrentStart),
			Period2Total = (SELECT Balance WHERE @P2Start IS NOT NULL AND (DueDate >= @P2Start OR @P3Start IS NULL) AND DueDate < @P1Start),
			Period3Total = (SELECT Balance WHERE @P3Start IS NOT NULL AND (DueDate >= @P3Start OR @P4Start IS NULL) AND DueDate < @P2Start),
			Period4Total = (SELECT Balance WHERE @P4Start IS NOT NULL AND DueDate < @P3Start),
			NotDue1Total = (SELECT Balance WHERE DueDate >= @P1PlusStart AND (DueDate < @P2PlusStart OR @P2PlusStart IS NULL)),
			NotDue2Total = (SELECT Balance WHERE DueDate >= @P2PlusStart AND (DueDate < @P3PlusStart OR @P3PlusStart IS NULL)),
			NotDue3Total = (SELECT Balance WHERE DueDate >= @P3PlusStart)
	END
END
ELSE IF @AgedByInvoiceDate = 'PST'
BEGIN
	IF @AgeingOption = 'PER'
	BEGIN
		IF @ShowLocalEquivalentTotal = 'Y'
		BEGIN
			UPDATE #TRANSACTIONS SET
				PeriodCurrent = (SELECT Balance WHERE PostDate IS NULL OR PostDate >= @PCurrentStart OR @P1Start IS NULL),
				Period1Total = (SELECT Balance WHERE @P1Start IS NOT NULL AND (PostDate >= @P1Start OR @P2Start IS NULL) AND PostDate < @PCurrentStart),
				Period2Total = (SELECT Balance WHERE @P2Start IS NOT NULL AND (PostDate >= @P2Start OR @P3Start IS NULL) AND PostDate < @P1Start),
				Period3Total = (SELECT Balance WHERE @P3Start IS NOT NULL AND (PostDate >= @P3Start OR @P4Start IS NULL) AND PostDate < @P2Start),
				Period4Total = (SELECT Balance WHERE @P4Start IS NOT NULL AND PostDate < @P3Start),
				PeriodCurrentInLocal = (SELECT BalanceInLocal WHERE PostDate IS NULL OR PostDate >= @PCurrentStart OR @P1Start IS NULL),
				Period1TotalInLocal = (SELECT BalanceInLocal WHERE @P1Start IS NOT NULL AND (PostDate >= @P1Start OR @P2Start IS NULL) AND PostDate < @PCurrentStart),
				Period2TotalInLocal = (SELECT BalanceInLocal WHERE @P2Start IS NOT NULL AND (PostDate >= @P2Start OR @P3Start IS NULL) AND PostDate < @P1Start),
				Period3TotalInLocal = (SELECT BalanceInLocal WHERE @P3Start IS NOT NULL AND (PostDate >= @P3Start OR @P4Start IS NULL) AND PostDate < @P2Start),
				Period4TotalInLocal = (SELECT BalanceInLocal WHERE @P4Start IS NOT NULL AND PostDate < @P3Start)
		END
		ELSE
		BEGIN
			UPDATE #TRANSACTIONS SET
				PeriodCurrent = (SELECT Balance WHERE PostDate IS NULL OR PostDate >= @PCurrentStart OR @P1Start IS NULL),
				Period1Total = (SELECT Balance WHERE @P1Start IS NOT NULL AND (PostDate >= @P1Start OR @P2Start IS NULL) AND PostDate < @PCurrentStart),
				Period2Total = (SELECT Balance WHERE @P2Start IS NOT NULL AND (PostDate >= @P2Start OR @P3Start IS NULL) AND PostDate < @P1Start),
				Period3Total = (SELECT Balance WHERE @P3Start IS NOT NULL AND (PostDate >= @P3Start OR @P4Start IS NULL) AND PostDate < @P2Start),
				Period4Total = (SELECT Balance WHERE @P4Start IS NOT NULL AND PostDate < @P3Start)
		END

	END
	ELSE
	BEGIN
		IF @ShowLocalEquivalentTotal = 'Y'
		BEGIN
			UPDATE #TRANSACTIONS SET
				PeriodCurrent = (SELECT Balance WHERE PostDate IS NULL OR PostDate >= @P1Start),
				Period1Total = (SELECT Balance WHERE PostDate >= @P2Start AND PostDate < @P1Start),
				Period2Total = (SELECT Balance WHERE PostDate >= @P3Start AND PostDate < @P2Start),
				Period3Total = (SELECT Balance WHERE PostDate >= @P4Start AND PostDate < @P3Start),
				Period4Total = (SELECT Balance WHERE PostDate < @P4Start),
				PeriodCurrentInLocal = (SELECT BalanceInLocal WHERE PostDate IS NULL OR PostDate >= @P1Start),
				Period1TotalInLocal = (SELECT BalanceInLocal WHERE PostDate >= @P2Start AND PostDate < @P1Start),
				Period2TotalInLocal = (SELECT BalanceInLocal WHERE PostDate >= @P3Start AND PostDate < @P2Start),
				Period3TotalInLocal = (SELECT BalanceInLocal WHERE PostDate >= @P4Start AND PostDate < @P3Start),
				Period4TotalInLocal = (SELECT BalanceInLocal WHERE PostDate < @P4Start)
		END
		ELSE
		BEGIN
			UPDATE #TRANSACTIONS SET
				PeriodCurrent = (SELECT Balance WHERE PostDate IS NULL OR PostDate >= @P1Start),
				Period1Total = (SELECT Balance WHERE PostDate >= @P2Start AND PostDate < @P1Start),
				Period2Total = (SELECT Balance WHERE PostDate >= @P3Start AND PostDate < @P2Start),
				Period3Total = (SELECT Balance WHERE PostDate >= @P4Start AND PostDate < @P3Start),
				Period4Total = (SELECT Balance WHERE PostDate < @P4Start)
		END
	END
END
ELSE IF @AgedByInvoiceDate = 'INV'
BEGIN
	IF @AgeingOption = 'PER'
	BEGIN
		IF @ShowLocalEquivalentTotal = 'Y'
		BEGIN
			UPDATE #TRANSACTIONS SET
				PeriodCurrent = (SELECT Balance WHERE InvoiceDate IS NULL OR InvoiceDate >= @PCurrentStart OR @P1Start IS NULL),
				Period1Total = (SELECT Balance WHERE @P1Start IS NOT NULL AND (InvoiceDate >= @P1Start OR @P2Start IS NULL) AND InvoiceDate < @PCurrentStart),
				Period2Total = (SELECT Balance WHERE @P2Start IS NOT NULL AND (InvoiceDate >= @P2Start OR @P3Start IS NULL) AND InvoiceDate < @P1Start),
				Period3Total = (SELECT Balance WHERE @P3Start IS NOT NULL AND (InvoiceDate >= @P3Start OR @P4Start IS NULL) AND InvoiceDate < @P2Start),
				Period4Total = (SELECT Balance WHERE @P4Start IS NOT NULL AND InvoiceDate < @P3Start),
				PeriodCurrentInLocal = (SELECT BalanceInLocal WHERE InvoiceDate IS NULL OR InvoiceDate >= @PCurrentStart OR @P1Start IS NULL),
				Period1TotalInLocal = (SELECT BalanceInLocal WHERE @P1Start IS NOT NULL AND (InvoiceDate >= @P1Start OR @P2Start IS NULL) AND InvoiceDate < @PCurrentStart),
				Period2TotalInLocal = (SELECT BalanceInLocal WHERE @P2Start IS NOT NULL AND (InvoiceDate >= @P2Start OR @P3Start IS NULL) AND InvoiceDate < @P1Start),
				Period3TotalInLocal = (SELECT BalanceInLocal WHERE @P3Start IS NOT NULL AND (InvoiceDate >= @P3Start OR @P4Start IS NULL) AND InvoiceDate < @P2Start),
				Period4TotalInLocal = (SELECT BalanceInLocal WHERE @P4Start IS NOT NULL AND InvoiceDate < @P3Start)
		END
		ELSE
		BEGIN
			UPDATE #TRANSACTIONS SET
				PeriodCurrent = (SELECT Balance WHERE InvoiceDate IS NULL OR InvoiceDate >= @PCurrentStart OR @P1Start IS NULL),
				Period1Total = (SELECT Balance WHERE @P1Start IS NOT NULL AND (InvoiceDate >= @P1Start OR @P2Start IS NULL) AND InvoiceDate < @PCurrentStart),
				Period2Total = (SELECT Balance WHERE @P2Start IS NOT NULL AND (InvoiceDate >= @P2Start OR @P3Start IS NULL) AND InvoiceDate < @P1Start),
				Period3Total = (SELECT Balance WHERE @P3Start IS NOT NULL AND (InvoiceDate >= @P3Start OR @P4Start IS NULL) AND InvoiceDate < @P2Start),
				Period4Total = (SELECT Balance WHERE @P4Start IS NOT NULL AND InvoiceDate < @P3Start)
		END

	END
	ELSE
	BEGIN
		IF @ShowLocalEquivalentTotal = 'Y'
		BEGIN
			UPDATE #TRANSACTIONS SET
				PeriodCurrent = (SELECT Balance WHERE InvoiceDate IS NULL OR InvoiceDate >= @P1Start),
				Period1Total = (SELECT Balance WHERE InvoiceDate >= @P2Start AND InvoiceDate < @P1Start),
				Period2Total = (SELECT Balance WHERE InvoiceDate >= @P3Start AND InvoiceDate < @P2Start),
				Period3Total = (SELECT Balance WHERE InvoiceDate >= @P4Start AND InvoiceDate < @P3Start),
				Period4Total = (SELECT Balance WHERE InvoiceDate < @P4Start),
				PeriodCurrentInLocal = (SELECT BalanceInLocal WHERE InvoiceDate IS NULL OR InvoiceDate >= @P1Start),
				Period1TotalInLocal = (SELECT BalanceInLocal WHERE InvoiceDate >= @P2Start AND InvoiceDate < @P1Start),
				Period2TotalInLocal = (SELECT BalanceInLocal WHERE InvoiceDate >= @P3Start AND InvoiceDate < @P2Start),
				Period3TotalInLocal = (SELECT BalanceInLocal WHERE InvoiceDate >= @P4Start AND InvoiceDate < @P3Start),
				Period4TotalInLocal = (SELECT BalanceInLocal WHERE InvoiceDate < @P4Start)
		END
		ELSE
		BEGIN
			UPDATE #TRANSACTIONS SET
				PeriodCurrent = (SELECT Balance WHERE InvoiceDate IS NULL OR InvoiceDate >= @P1Start),
				Period1Total = (SELECT Balance WHERE InvoiceDate >= @P2Start AND InvoiceDate < @P1Start),
				Period2Total = (SELECT Balance WHERE InvoiceDate >= @P3Start AND InvoiceDate < @P2Start),
				Period3Total = (SELECT Balance WHERE InvoiceDate >= @P4Start AND InvoiceDate < @P3Start),
				Period4Total = (SELECT Balance WHERE InvoiceDate < @P4Start)
		END
	END
END

--------------------------------------------------------------------------------------------
-- UDPATE LineInvoiceExTaxAmount and LineTaxAmount
--------------------------------------------------------------------------------------------
IF @ShowLineAmounts = 'Y'
BEGIN
	UPDATE #TRANSACTIONS
	SET LineInvoiceExTaxAmount = SumExTax, LineTaxAmount = SumTax
	FROM #TRANSACTIONS INNER JOIN(
		SELECT 
			tx.TransactionPK as TransactionPKInner, sum(l.AL_LineAmount) as SumExTax, sum(l.AL_GSTVAT) as SumTax
		FROM 
			#TRANSACTIONS tx
			INNER JOIN AccTransactionLines l ON l.AL_AH = tx.TransactionPK
		WHERE
			tx.TransactionType in ('INV','CRD','ADJ')
		GROUP BY tx.TransactionPK
	) TxSum ON TransactionPK = TxSum.TransactionPKInner
	OPTION(RECOMPILE);
END

--------------------------------------------------------------------------------------------
-- Update 'Use Settlement Group Credit Limit'
--------------------------------------------------------------------------------------------
IF @LedgerType = 'AR'
BEGIN 
	UPDATE 
		#Transactions
	SET
		ARUseSettlementGroupCreditLimit = OB_ARUseSettlementGroupCreditLimit,
		UsingOrgAsOwnSettlementGroup = CASE WHEN OB_ARUseSettlementGroupCreditLimit = 1 THEN 'N' ELSE 'Y' END
	FROM
		OrgCompanyData INNER JOIN OrgHeader ON OB_OH = OH_PK 
	WHERE 
		OH_PK = #Transactions.AccountPK	 AND OB_GC = @Company
END

IF @LedgerType = 'AP'
BEGIN 
	UPDATE 
		#Transactions
	SET
		UsingOrgAsOwnSettlementGroup = 'N'
END

IF @LedgerType = 'AR' OR @LedgerType = 'AP'
BEGIN 
	UPDATE 
		#Transactions
	SET
		SettlementGroupCreditLimit = CASE WHEN @LedgerType = 'AR' THEN 
			(SELECT AdjustedCreditLimit FROM OrgAdjustedCreditLimit(OB_ARCreditLimit, OB_ARTemporaryCreditLimitIncrease, OB_ARTemporaryCreditLimitIncreaseExpiry))
		ELSE 
			OB_APCreditLimit 
		END
	FROM
		OrgCompanyData 
		INNER JOIN OrgRelatedParty ON PR_OH_RelatedParty = OB_OH 
		INNER JOIN OrgHeader ON OB_OH = OH_PK AND OB_GC = PR_GC
	WHERE
			PR_OH_Parent = #Transactions.AccountPK AND 
			PR_PartyType = CASE WHEN @LedgerType = 'AR' THEN 'ARS' ELSE 'APS' END AND 
			UsingOrgAsOwnSettlementGroup = 'N' AND
			PR_GC = @Company;
	
	UPDATE 
		#Transactions
	SET
		SettlementGroupCreditLimit = CASE WHEN @LedgerType = 'AR' THEN 
			(SELECT AdjustedCreditLimit FROM OrgAdjustedCreditLimit(OB_ARCreditLimit, OB_ARTemporaryCreditLimitIncrease, OB_ARTemporaryCreditLimitIncreaseExpiry))
		ELSE
			OB_APCreditLimit
		END
	FROM
		OrgCompanyData 
		INNER JOIN OrgHeader ON OB_OH = OH_PK 
	WHERE 
		OH_PK = #Transactions.AccountPK AND
		OB_GC = @Company AND 
		UsingOrgAsOwnSettlementGroup = 'Y';

	WITH 
	BaseSettlementGroup AS 
	(
		SELECT	PR_OH_RelatedParty,PR_OH_Parent
		FROM	OrgRelatedParty
		INNER JOIN OrgCompanyData
			ON PR_OH_Parent = OB_OH		
		WHERE	PR_PartyType = CASE WHEN @LedgerType = 'AR' THEN 'ARS' ELSE 'APS' END AND 
				PR_GC = @Company AND OB_ARUseSettlementGroupCreditLimit = 1
	)
	UPDATE 
		#Transactions
	SET
		SettlementGroupOutstandingAmount =
			(
			SELECT SUM(AH_OutstandingAmount) FROM AccTransactionHeader
			WHERE 
				AH_TransactionType != 'INB' AND
				AH_Ledger = @LedgerType AND
				AH_OH IN(
							SELECT PR_OH_Parent FROM BaseSettlementGroup WHERE PR_OH_RelatedParty IN (SELECT PR_OH_RelatedParty FROM  BaseSettlementGroup WHERE PR_OH_Parent = #Transactions.AccountPK) 
							UNION ALL
							SELECT PR_OH_RelatedParty FROM  BaseSettlementGroup WHERE PR_OH_Parent = #Transactions.AccountPK
						) 
				AND AH_GC = @Company
				
			) WHERE UsingOrgAsOwnSettlementGroup = 'N'
			OPTION(RECOMPILE);

	WITH 
	BaseSettlementGroup AS 
	(
		SELECT	PR_OH_RelatedParty,PR_OH_Parent
		FROM	OrgRelatedParty
		INNER JOIN OrgCompanyData
			ON PR_OH_Parent = OB_OH		
		WHERE	PR_PartyType = CASE WHEN @LedgerType = 'AR' THEN 'ARS' ELSE 'APS' END AND 
				PR_GC = @Company AND OB_ARUseSettlementGroupCreditLimit = 1
	)
	UPDATE 
		#Transactions
	SET
		SettlementGroupOutstandingAmount =
			(
			SELECT SUM(AH_OutstandingAmount) FROM AccTransactionHeader 
			WHERE 
				AH_TransactionType != 'INB' AND
				AH_Ledger = @LedgerType AND
				AH_OH IN(
							SELECT PR_OH_Parent FROM BaseSettlementGroup WHERE PR_OH_RelatedParty = #Transactions.AccountPK 
							UNION ALL
							SELECT #Transactions.AccountPK
						)
				AND AH_GC = @Company			
			) WHERE UsingOrgAsOwnSettlementGroup = 'Y'
			OPTION(RECOMPILE);

	UPDATE 
		#Transactions
	SET
		SettlementGroupOverCreditLimit = CASE WHEN SettlementGroupOutstandingAmount > SettlementGroupCreditLimit THEN 'Y' ELSE 'N' END 
END

IF @OverLimitOnly = 'Y'
BEGIN
	DELETE FROM #Transactions WHERE SettlementGroupOverCreditLimit <> 'Y'
END

--------------------------------------------------------------------------------------------
-- Update 'MatchStatus' and 'MatchStatusReason'
--------------------------------------------------------------------------------------------
IF @ShowMatchStatusAndReason = 'Y'
BEGIN
	UPDATE 
		#Transactions
	SET 
		MatchStatus =  (CASE WHEN MatchStatusWithDescription.[Description] is null THEN MatchStatus ELSE MatchStatus + ' - ' + MatchStatusWithDescription.[Description] END),
		MatchStatusReason = (CASE WHEN MatchStatusReasonWithDescription.[Description] is null THEN MatchStatusReason ELSE MatchStatusReason + ' - ' + MatchStatusReasonWithDescription.[Description] END)
	FROM
		#Transactions
	LEFT JOIN
		Report_GetMatchStatusWithDescription(@company) MatchStatusWithDescription ON MatchStatus = MatchStatusWithDescription.Code
	LEFT JOIN
		Report_GetMatchStatusReasonWithDescription(@company) MatchStatusReasonWithDescription ON MatchStatusReason = MatchStatusReasonWithDescription.Code
END

--------------------------------------------------------------------------------------------
-- Detailed OR SummaryOnly 
--------------------------------------------------------------------------------------------
IF @SummaryOnly = 'Y' OR @ShowAddUser <> 'Y'
BEGIN
	UPDATE 
		#Transactions
	SET 
		OperatorInitials = ''
	FROM
		#Transactions
END

IF @SummaryOnly <> 'Y'
BEGIN	

	IF @OrderBy = 'TRN'
	BEGIN
		SELECT * FROM #TRANSACTIONS ORDER BY AccountCode, InvoiceRef
	END
	ELSE IF @OrderBy = 'Post Date, Type then Transaction Number'
	BEGIN
		SELECT * FROM #TRANSACTIONS WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE()) ORDER BY (select convert(date, PostDate)), TransactionType, InvoiceRef
	END
	ELSE IF @OrderBy = 'Invoice Date, Type then Transaction Number'
	BEGIN
		SELECT * FROM #TRANSACTIONS WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE()) ORDER BY (select convert(date, InvoiceDate)), TransactionType, InvoiceRef
	END
	ELSE IF @OrderBy = 'Transaction Type then Transaction Number'
	BEGIN
		SELECT * FROM #TRANSACTIONS WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE()) ORDER BY TransactionType, InvoiceRef, (select convert(date, PostDate))
	END
	ELSE IF @OrderBy = 'Transaction Number then Transaction Type'
	BEGIN
		SELECT * FROM #TRANSACTIONS WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE()) ORDER BY InvoiceRef, TransactionType, (select convert(date, PostDate))
	END
	ELSE
	BEGIN
		SELECT *, RevaluedLocalEquivalent-BalanceInLocal AS GainLossOnRevaluation,
					CASE WHEN (@LedgerType = 'AR' AND (RevaluedLocalEquivalent-BalanceInLocal) >= 0) OR (@LedgerType = 'AP' AND (RevaluedLocalEquivalent-BalanceInLocal) <= 0)
					THEN ABS(RevaluedLocalEquivalent-BalanceInLocal)
					ELSE NULL
					END AS GainOnRevaluation,
					CASE WHEN (@LedgerType = 'AR' AND (RevaluedLocalEquivalent-BalanceInLocal) < 0) OR (@LedgerType = 'AP' AND (RevaluedLocalEquivalent-BalanceInLocal) > 0)
					THEN ABS(RevaluedLocalEquivalent-BalanceInLocal)
					ELSE NULL
					END AS LossOnRevaluation
			FROM
			(SELECT *,	
				CASE WHEN PeriodEndRate IS NULL THEN BalanceInLocal
					 ELSE CASE WHEN @IsReciprocal = 1
							THEN Balance*PeriodEndRate
							ELSE Balance/PeriodEndRate
						  END
				END AS RevaluedLocalEquivalent 
			FROM
				(SELECT *, RE_SellRate AS PeriodEndRate FROM #TRANSACTIONS
				LEFT JOIN RefCurrency ON RX_PK = CurrencyPK
				LEFT JOIN RefExchangeRate ON
								RefExchangeRate.RE_RX_NKExCurrency = RX_Code
								AND RefExchangeRate.RE_GC = @Company
								AND RefExchangeRate.RE_StartDate <= Cast(Floor(Cast(@PCurrentEnd AS float)) AS DateTime)
								AND RefExchangeRate.RE_ExpiryDate >= Cast(Floor(Cast(@PCurrentEnd AS float)) AS DateTime)
								AND RefExchangeRate.RE_ExRateType IN (SELECT ExchangeRateType FROM dbo.GetAdjustmentExchangeRateType(@Company))
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				)DetailTableNotFull) DetailTable
		ORDER BY AccountCode, InvoiceDate
	END
END
ELSE
BEGIN
	IF @ShowAllTransactions = 'Y'
	BEGIN
		IF @GroupBy = 'Transaction Type'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode
				ORDER BY TransactionType
		END
		ELSE IF @GroupBy = 'Consolidation Category'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				ConsolidationCategory
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode, ConsolidationCategory
				ORDER BY TransactionType
		END
		ELSE IF @GroupBy = 'Accounts Relationship'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				ARCategory
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode, ARCategory
				ORDER BY TransactionType
		END
		ELSE IF @GroupBy = 'Organisation Branch'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				OrgBranchCode, OrgBranchName
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode, OrgBranchCode, OrgBranchName
				ORDER BY TransactionType
		END
		ELSE IF @GroupBy = 'Transaction Branch'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				BranchCode, CountryCode, TranBranchName
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode, BranchCode, TranBranchName, CountryCode 
				ORDER BY TransactionType
		END
		ELSE IF @GroupBy = 'Sales Rep'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				SalesRep, SalesRepName
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode, SalesRep, SalesRepName
				ORDER BY TransactionType
		END
		ELSE IF @GroupBy = 'Credit Controller'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				CreditController, CreditControllerName
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode, CreditController, CreditControllerName
				ORDER BY TransactionType
		END
		ELSE IF @GroupBy = 'Customer Service Rep'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				CustomerService, CustomerServiceName
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode, CustomerService, CustomerServiceName
				ORDER BY TransactionType
		END
		ELSE IF @GroupBy = 'Settlement Group'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				SettlementCode, SettlementName
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode, SettlementCode, SettlementName
				ORDER BY TransactionType
		END
		ELSE IF @GroupBy = 'Debtor Group' OR @GroupBy = 'Creditor Group'
		BEGIN
			SELECT SUM(OSTotal) AS OSTotal, SUM(InvoiceTotal) AS InvoiceTotal, SUM(InvoiceExTax) AS InvoiceExTax, SUM(TaxAmount) AS TaxAmount,
				TransactionType, TransactionTypeDesc, CurrencyCode, Count(*) AS NoOfTransactions, SUM(OSTotal)/Count(*) AS FXAvg, SUM(InvoiceTotal)/Count(*) AS LocalAvg, SUM(LineInvoiceExTaxAmount) AS LineInvoiceExTaxAmount, SUM(LineTaxAmount) AS LineTaxAmount,(SUM(LineInvoiceExTaxAmount) + SUM(LineTaxAmount)) as LinesSum,
				AccountGroup
				FROM #TRANSACTIONS
				WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
				GROUP BY TransactionType, TransactionTypeDesc, CurrencyCode, AccountGroup
				ORDER BY TransactionType
		END
	END
	ELSE
	BEGIN
		IF @GroupBy = 'Transaction Currency, Transaction Branch then Organization' OR @GroupBy = 'Transaction Currency, Transaction Branch then Organisation' set @GroupBy ='Transaction Branch'
		SELECT *, RevaluedLocalEquivalent-BalanceInLocal AS GainLossOnRevaluation
				FROM
						(SELECT AccountCode, AccountName, CreditLimit, OrgBranchCode, AccountGroup, SalesRep, CustomerService, CreditController, IsOverLimit, 
							SUM(NotDue1Total) AS NotDue1Total, SUM(NotDue2Total) AS NotDue2Total, SUM(NotDue3Total) AS NotDue3Total, SUM(NotDue4Total) AS NotDue4Total,
							SUM(Period1Total) AS Period1Total, SUM(Period2Total) AS Period2Total, SUM(Period3Total) AS Period3Total, SUM(Period4Total) AS Period4Total, 
							SUM(PeriodCurrent) AS PeriodCurrent, SUM(DSBCharge) AS DSBCharge, SUM(Balance) AS Balance, 
							SUM(NotDue1TotalInLocal) AS NotDue1TotalInLocal, SUM(NotDue2TotalInLocal) AS NotDue2TotalInLocal, SUM(NotDue3TotalInLocal) AS NotDue3TotalInLocal, SUM(NotDue4TotalInLocal) AS NotDue4TotalInLocal,
							SUM(Period1TotalInLocal) AS Period1TotalInLocal, SUM(Period2TotalInLocal) AS Period2TotalInLocal, SUM(Period3TotalInLocal) AS Period3TotalInLocal, SUM(Period4TotalInLocal) AS Period4TotalInLocal, 
							SUM(PeriodCurrentInLocal) AS PeriodCurrentInLocal, SUM(BalanceInLocal) AS BalanceInLocal, SUM(MatchedInFuturePeriodInInvoiceCurrency) AS MatchedInFuturePeriodInInvoiceCurrency, 
							SUM(MatchedInFuturePeriodInLocalCurrency) AS MatchedInFuturePeriodInLocalCurrency,
							SUM(RevaluedLocalEquivalent) AS RevaluedLocalEquivalent,
							SUM(LossOnRevaluation) as LossOnRevaluation, SUM(GainOnRevaluation) as GainOnRevaluation,
							ConsolidationCategory, ARCategory, SettlementCode, CountryCode, CountryName,
							OrgBranchName, SalesRepName, CreditControllerName, CustomerServiceName, SettlementName, 
							CASE @ShowInInvoicedCurrency 
								WHEN 'Y' THEN CurrencyCode
								ELSE NULL
							END AS CurrencyCode,
							CASE @ShowInInvoicedCurrency 
								WHEN 'Y' THEN CurrencyPK
								ELSE NULL
							END AS CurrencyPK,
							PeriodEndRate,
							ContactPhoneNo, 
							dbo.CLRCssvAgg(distinct LTRIM(RTRIM(ISNULL(InvoiceTerm, '')))) as InvoiceTerm,
							CASE WHEN SUM(BalanceInLocal)=0 OR SUM(Balance)=0 THEN NULL
								 ELSE CASE WHEN @IsReciprocal = 1
										THEN SUM(BalanceInLocal)/Convert(decimal(21,6),SUM(Balance))
										ELSE Convert(decimal(21,6),SUM(Balance))/SUM(BalanceInLocal)
									  END
							END AS AverageExchangeRate 
							,ARUseSettlementGroupCreditLimit
							,SettlementGroupCreditLimit
							,SettlementGroupOutstandingAmount
							,CASE WHEN @GroupBy = 'Transaction Branch' THEN  BranchCode ELSE NULL END BranchCode
							,CASE WHEN @GroupBy = 'Transaction Branch' THEN  TranBranchName ELSE NULL END TranBranchName
							,SettlementGroupOverCreditLimit
							,AdditionalCompanyName
							FROM
							(
								SELECT *,
									CASE WHEN (@LedgerType = 'AR' AND (RevaluedLocalEquivalent-BalanceInLocal) >= 0) OR (@LedgerType = 'AP' AND (RevaluedLocalEquivalent-BalanceInLocal) <= 0)
									THEN ABS(RevaluedLocalEquivalent-BalanceInLocal)
									ELSE NULL
									END AS GainOnRevaluation,
									CASE WHEN (@LedgerType = 'AR' AND (RevaluedLocalEquivalent-BalanceInLocal) < 0) OR (@LedgerType = 'AP' AND (RevaluedLocalEquivalent-BalanceInLocal) > 0)
									THEN ABS(RevaluedLocalEquivalent-BalanceInLocal)
									ELSE NULL
									END AS LossOnRevaluation
									FROM
									(
										SELECT *,
										CASE WHEN PeriodEndRate IS NULL THEN BalanceInLocal
											ELSE CASE WHEN @IsReciprocal = 1
											THEN Balance*PeriodEndRate
											ELSE Balance/PeriodEndRate
											END
										END AS RevaluedLocalEquivalent 
										FROM #TRANSACTIONS
										LEFT JOIN RefCurrency ON RX_PK = CurrencyPK
										LEFT JOIN 
												(select *, CASE @ShowInInvoicedCurrency 
															WHEN 'Y' THEN RE_SellRate
															ELSE NULL
															END AS PeriodEndRate 
													FROM RefExchangeRate)
													RefExchangeRate ON 
													RefExchangeRate.RE_RX_NKExCurrency =  RX_Code
													AND RefExchangeRate.RE_GC = @Company
													AND RefExchangeRate.RE_StartDate <= Cast(Floor(Cast(@PCurrentEnd AS float)) AS DateTime)
													AND RefExchangeRate.RE_ExpiryDate >= Cast(Floor(Cast(@PCurrentEnd AS float)) AS DateTime)
													AND RefExchangeRate.RE_ExRateType IN (SELECT ExchangeRateType FROM dbo.GetAdjustmentExchangeRateType(@Company))
								
												WHERE (@OverdueTransactions = 'N' OR  DueDate <= GETDATE())
									) RevaluedLocalEquivalentTable
							) SummaryTableNotFull
								GROUP BY AccountCode, AccountName, CreditLimit, OrgBranchCode, AccountGroup, SalesRep, CustomerService, CreditController, IsOverLimit,
								ConsolidationCategory, ARCategory, SettlementCode, OrgBranchName, CountryCode, CountryName, 
								SalesRepName, CreditControllerName, CustomerServiceName, SettlementName,ContactPhoneNo,PeriodEndRate,
								CASE @ShowInInvoicedCurrency 
									WHEN 'Y' THEN CurrencyCode
									ELSE NULL
								END,
								CASE @ShowInInvoicedCurrency 
									WHEN 'Y' THEN CurrencyPK
									ELSE NULL
								END,
								CASE @ShowInInvoicedCurrency 
									WHEN 'Y' THEN RE_SellRate
									ELSE NULL
								END
								,ARUseSettlementGroupCreditLimit
								,SettlementGroupCreditLimit
								,SettlementGroupOutstandingAmount
								,CASE WHEN @GroupBy = 'Transaction Branch' THEN BranchCode ELSE NULL END
								,CASE WHEN @GroupBy = 'Transaction Branch' THEN TranBranchName ELSE NULL END
								,SettlementGroupOverCreditLimit
								,AdditionalCompanyName
						) SummaryTable
						ORDER BY	CASE WHEN @OrderBy = 'SalesRepName' THEN SalesRepName WHEN @OrderBy = 'SettlementCode' THEN SettlementCode ELSE AccountCode END	
	END
END

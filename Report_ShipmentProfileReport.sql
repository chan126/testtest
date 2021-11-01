CREATE FUNCTION Report_ShipmentProfileReport 
(
	@CurrentCountry               varchar(2),
	@CompanyPK                    uniqueidentifier,
	@OrderedStorageClassCodesList varchar(1000),
	@Origin                       varchar(5),
	@Destination                  varchar(5),
	@Direction                    varchar(3),
	@RelatedClientType            varchar(3),
	@RelatedPartyType             varchar(3),
	@RelatedParty                 uniqueidentifier,
	@CoLoadType                   varchar(3),
	@IncludeInactive              char(1),
	@JobRevFrom                   datetime,
	@JobRevTo                     datetime,
	@TransactionFrom              datetime,
	@TransactionTo                datetime
)

RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN

WITH

ShipmentEntryNumbers AS
(
	SELECT
		JS,
		EntryNumbers = dbo.CLRConcatenateAgg(CE_EntryType + ' ' + CE_EntryNum, char(10), 0)
	FROM
		(
			SELECT DISTINCT
				JS = Parent.JS,
				CE_EntryType, CE_EntryNum
			FROM
				dbo.CusEntryNum 
				JOIN
				(
					SELECT
						JS       = JS_PK,
						ParentID = JS_PK
					FROM
						dbo.JobShipment 

					UNION ALL

					SELECT
						JS       = JE_JS,
						ParentID = ParentID
					FROM 
						(
							SELECT JE_JS, JE_PK, CH_PK
							FROM dbo.JobDeclaration 
							LEFT JOIN dbo.CusEntryHeader ON JE_PK = CH_JE 
						) AS p
						UNPIVOT (ParentID FOR Parent in (JE_PK, CH_PK)) AS unpvt

					UNION ALL

					SELECT
						JS       = CS_JS,
						ParentID = CS_CM
					FROM
						dbo.CusHAWB 

				) AS Parent ON Parent.ParentID = CE_ParentID
			WHERE
				CE_Category = 'CUS'
				AND CE_ParentTable in ('JobShipment', 'JobDeclaration', 'CusEntryHeader', 'CusMAWB')
		) AS t

	GROUP BY
		JS
),

AccTransactionLinesCTE AS
(
	SELECT
		JH 										= ATFilteredLines.JH,

		HeaderAmountsPostDate_AL_LineAmount 	= SUM(ATFilteredLines.HeaderAmountsPostDate_AL_LineAmount),
		HeaderAmountsPostDate_WIPAmount 		= SUM(ATFilteredLines.HeaderAmountsPostDate_WIPAmount),
		HeaderAmountsPostDate_ACRAmount 		= SUM(ATFilteredLines.HeaderAmountsPostDate_ACRAmount),

		HeaderAmountsReverseDate_AL_LineAmount 	= SUM(ATFilteredLines.HeaderAmountsReverseDate_AL_LineAmount),
		HeaderAmountsReverseDate_WIPAmount 		= SUM(ATFilteredLines.HeaderAmountsReverseDate_WIPAmount),
		HeaderAmountsReverseDate_ACRAmount 		= SUM(ATFilteredLines.HeaderAmountsReverseDate_ACRAmount),
		HeaderAmountsReverseDate_CSTAmount 		= SUM(ATFilteredLines.HeaderAmountsReverseDate_CSTAmount),
		HeaderAmountsReverseDate_REVAmount 		= SUM(ATFilteredLines.HeaderAmountsReverseDate_REVAmount),

		HeaderAmountsREVCST_AL_LineAmount  		= SUM(ATFilteredLines.HeaderAmountsREVCST_AL_LineAmount),
		HeaderAmountsREVCST_UnRecogCSTAmount 	= SUM(ATFilteredLines.HeaderAmountsREVCST_UnRecogCSTAmount),
		HeaderAmountsREVCST_UnRecogREVAmount 	= SUM(ATFilteredLines.HeaderAmountsREVCST_UnRecogREVAmount)
	FROM
	(
		(
			SELECT
				JH            							= AL_JH,

				HeaderAmountsPostDate_AL_LineAmount 	= SUM(-CAST(AL_LineAmount AS DECIMAL(24, 9))),
				HeaderAmountsPostDate_WIPAmount     	= SUM(CASE WHEN AL_LineType = 'WIP' THEN -CAST(AL_LineAmount AS DECIMAL(24, 9)) ELSE 0 END),
				HeaderAmountsPostDate_ACRAmount     	= SUM(CASE WHEN AL_LineType = 'ACR' THEN -CAST(AL_LineAmount AS DECIMAL(24, 9)) ELSE 0 END),

				HeaderAmountsReverseDate_AL_LineAmount 	= 0,
				HeaderAmountsReverseDate_WIPAmount 		= 0,
				HeaderAmountsReverseDate_ACRAmount 		= 0,
				HeaderAmountsReverseDate_CSTAmount 		= 0,
				HeaderAmountsReverseDate_REVAmount 		= 0,

				HeaderAmountsREVCST_AL_LineAmount 		= 0,
				HeaderAmountsREVCST_UnRecogCSTAmount 	= 0,
				HeaderAmountsREVCST_UnRecogREVAmount 	= 0
			FROM
				dbo.AccTransactionLines
			WHERE
				AL_LineType in ('ACR', 'WIP')
				AND AL_PostDate >= @TransactionFrom AND AL_PostDate < @TransactionTo
			GROUP BY
				AL_JH
		)
		UNION
		(
			SELECT
				JH            							= AL_JH,

				HeaderAmountsPostDate_AL_LineAmount 	= 0,
				HeaderAmountsPostDate_WIPAmount     	= 0,
				HeaderAmountsPostDate_ACRAmount     	= 0,

				HeaderAmountsReverseDate_AL_LineAmount 	= SUM(CAST(AL_LineAmount AS DECIMAL(24, 9))),
				HeaderAmountsReverseDate_WIPAmount     	= SUM(CASE WHEN AL_LineType = 'WIP' THEN CAST(AL_LineAmount AS DECIMAL(24, 9)) ELSE 0 END),
				HeaderAmountsReverseDate_ACRAmount     	= SUM(CASE WHEN AL_LineType = 'ACR' THEN CAST(AL_LineAmount AS DECIMAL(24, 9)) ELSE 0 END),
				HeaderAmountsReverseDate_CSTAmount     	= SUM(CASE WHEN AL_LineType = 'CST' THEN CAST(AL_LineAmount AS DECIMAL(24, 9)) ELSE 0 END),
				HeaderAmountsReverseDate_REVAmount     	= SUM(CASE WHEN AL_LineType = 'REV' THEN CAST(AL_LineAmount AS DECIMAL(24, 9)) ELSE 0 END),

				HeaderAmountsREVCST_AL_LineAmount 		= 0,
				HeaderAmountsREVCST_UnRecogCSTAmount 	= 0,
				HeaderAmountsREVCST_UnRecogREVAmount 	= 0
			FROM
				dbo.AccTransactionLines
			WHERE
				AL_LineType in ('ACR', 'WIP', 'REV', 'CST')
				AND AL_ReverseDate >= @TransactionFrom AND AL_ReverseDate < @TransactionTo
			GROUP BY
				AL_JH
		)
		UNION
		(
			SELECT
				JH            							= AL_JH,

				HeaderAmountsPostDate_AL_LineAmount 	= 0,
				HeaderAmountsPostDate_WIPAmount     	= 0,
				HeaderAmountsPostDate_ACRAmount     	= 0,

				HeaderAmountsReverseDate_AL_LineAmount 	= 0,
				HeaderAmountsReverseDate_WIPAmount 		= 0,
				HeaderAmountsReverseDate_ACRAmount 		= 0,
				HeaderAmountsReverseDate_CSTAmount 		= 0,
				HeaderAmountsReverseDate_REVAmount 		= 0,

				HeaderAmountsREVCST_AL_LineAmount 		= SUM(CAST(AL_LineAmount AS DECIMAL(24, 9))),
				HeaderAmountsREVCST_UnRecogCSTAmount 	= SUM(CASE WHEN AL_LineType = 'CST' AND @TransactionFrom = '1900-01-01 00:00:00' AND @TransactionTo = '2079-06-06 23:59:29' THEN CAST(AL_LineAmount AS DECIMAL(24, 9)) ELSE 0 END),
				HeaderAmountsREVCST_UnRecogREVAmount 	= SUM(CASE WHEN AL_LineType = 'REV' AND @TransactionFrom = '1900-01-01 00:00:00' AND @TransactionTo = '2079-06-06 23:59:29' THEN CAST(AL_LineAmount AS DECIMAL(24, 9)) ELSE 0 END)
			FROM
				dbo.AccTransactionLines
			WHERE
					AL_LineType in ('REV', 'CST') AND
					AL_ReverseDate IS NULL
			GROUP BY
				AL_JH
		)
	) AS ATFilteredLines
	WHERE
		(@TransactionFrom = '1900-01-01 00:00:00' AND @TransactionTo = '2079-06-06 23:59:29')
		OR
		(
			@TransactionFrom > '1900-01-01 00:00:00' AND @TransactionTo < '2079-06-06 23:59:29'
			AND
			EXISTS
			(
				SELECT AL_PK
				FROM dbo.AccTransactionLines 
				WHERE
					(
						(
							AL_LineType in ('ACR', 'WIP') AND 
							(
								(AL_PostDate >= @TransactionFrom AND AL_PostDate < @TransactionTo)
								OR
								(AL_ReverseDate >= @TransactionFrom AND AL_ReverseDate < @TransactionTo)
							)
						)
						OR
						(
							AL_LineType in ('REV', 'CST') AND 
							AL_ReverseDate >= @TransactionFrom AND AL_ReverseDate < @TransactionTo
						)
					)
			)
		)
	GROUP BY JH
)

SELECT
	--SHIPMENT DETAILS
	HeaderExists      = CASE WHEN JH_PK is NOT NULL THEN 'Y' ELSE NULL END,
	ShipmentID        = JS.JS_UniqueConsignRef,
	Type              = JS.JS_TransportMode,
	Mode              = JS.JS_PackingMode,
	Origin            = JS.JS_RL_NKOrigin,
	INCO              = JS.JS_INCO,
	Terms             = IncotermDetails.Value,
	AdditionalTerms   = JS.JS_AdditionalTerms,
	Dest              = JS.JS_RL_NKDestination,

	ConsignorPK       = Consignor.OH_PK,
	ConsignorCode     = Consignor.OH_Code,
	ConsignorName     = Consignor.FullName,
	ConsignorCity     = Consignor.City,
	ConsignorState    = Consignor.[State],
	ConsignorPostCode = Consignor.PostCode,

	ConsigneePK       = Consignee.OH_PK,
	ConsigneeCode     = Consignee.OH_Code,
	ConsigneeName     = Consignee.FullName,
	ConsigneeCity     = Consignee.City,
	ConsigneeState    = Consignee.[State],
	ConsigneePostCode = Consignee.PostCode,

	CusEntryInfo = CusNums.EntryNumbers,

	CarrierContractNumbers = STUFF
	((
		SELECT
			char(10) + CE_EntryNum
		FROM
			dbo.CusEntryNum 
			JOIN dbo.JobConShipLink ON CE_ParentID = JN_JK AND CE_ParentTable = 'JobConsol' 
		WHERE
			JN_JS = JS.JS_PK
			AND CE_Category = 'OTH'
			AND CE_EntryType = 'CON'
		FOR XML PATH('')
	), 1, 1, ''),

	HouseBill     = JS.JS_HouseBill,
	HouseBillType = JS.JS_HouseBillOfLadingType,
	ETD           = JS.JS_E_DEP,
	ETA           = JS.JS_E_ARV,
	Weight        = JS.JS_ActualWeight,
	Volume        = JS.JS_ActualVolume,
	WeightUnit    = JS.JS_UnitOfWeight,
	VolumeUnit    = JS.JS_UnitOfVolume,
	LoadingMeters = JS.JS_LoadingMeters,
	Chargeable    = JS.JS_ActualChargeable,
	IsActive      = CASE JS.JS_IsCancelled WHEN 1 THEN 'N' ELSE 'Y' END,

	ChargeableUnit = ChargeableUnitValue.Value,

	Inners              = JS.JS_TotalPackageCount,
	InnersType          = JS.JS_F3_NKTotalCountPackType,
	Outers              = JS.JS_OuterPacks,
	OutersType          = JS.JS_F3_NKPackType,
	RegisteredDate      = JS.JS_SystemCreateTimeUtc,
	JS_GoodsDescription = JS.JS_GoodsDescription,

	Declaration         = CASE WHEN JE_JS is NULL THEN 'N' ELSE 'Y' END,
	Transport           = CASE WHEN JJ_ParentID is NULL THEN 'N' ELSE 'Y' END,
	Direction			= CASE JS.JS_Direction
							WHEN 'IMP' THEN 'Import'
							WHEN 'EXP' THEN 'Export'
							WHEN 'OTH' THEN 'Other/Cross Trade'
						  END,

	ShipmentControllingCustomerPK   = ControllingCustomer.OH_PK,
	ShipmentControllingCustomerCode = ControllingCustomer.OH_Code,
	ShipmentControllingCustomerName = ControllingCustomer.FullName,

	ShipmentControllingAgentPK   = ControllingAgent.OH_PK,
	ShipmentControllingAgentCode = ControllingAgent.OH_Code,
	ShipmentControllingAgentName = ControllingAgent.FullName,

	--CONSOL DETAILS
	ConsolID    = Consol.JK_UniqueConsignRef,
	MasterBill  = Consol.JK_MasterBillNum,

	LoadPort      = MainConTrans.JW_RL_NKLoadPort,
	DischargePort = MainConTrans.JW_RL_NKDiscPort,
	Vessel        = MainConTrans.JW_Vessel,
	Voyage        = MainConTrans.JW_VoyageFlight,
	JW_ETD        = MainConTrans.JW_ETD,
	JW_ETA        = MainConTrans.JW_ETA,

	JW_ATD        = MainConTrans.JW_ATD,
	JW_ATA        = MainConTrans.JW_ATA,

	SendAgentCode = SendingAgent.OH_Code,
	SendAgentName = SendingAgent.OH_FullName,
	RecvAgentCode = ReceivingAgent.OH_Code,
	RecvAgentName = ReceivingAgent.OH_FullName,
	CoLoadCode    = CoLoad.OH_Code,
	CoLoadName    = CoLoad.OH_FullName,

	--JOB INVOICE SUMMARY
	BranchPK            = JH_GB,
	Branch              = GB_Code,
	DepartmentPK        = JH_GE,
	Dept                = GE_Code,

	LocalClientPK                       = LocalClient.OH_PK,
	LocalClient                         = LocalClient.OH_Code,
	LocalClientFullName                 = LocalClient.OH_FullName,
	LocalClientARSettlementGroupCode    = LocalClientARSettleGroupOrgHeader.OH_Code,
	LocalClientARSettlementGroupName    = LocalClientARSettleGroupOrgHeader.OH_FullName,

	Amount              = NULLIF(ISNULL(HeaderAmountsPostDate_AL_LineAmount, .0000) + ISNULL(HeaderAmountsReverseDate_AL_LineAmount, .0000) + ISNULL(HeaderAmountsREVCST_AL_LineAmount, .0000), .0000), --aka JobProfit
	REVAmount           = ISNULL(HeaderAmountsReverseDate_REVAmount, .0000),
	WIPAmount           = ISNULL(HeaderAmountsPostDate_WIPAmount, .0000) + ISNULL(HeaderAmountsReverseDate_WIPAmount, .0000),
	ACRAmount           = ISNULL(HeaderAmountsPostDate_ACRAmount, .0000) + ISNULL(HeaderAmountsReverseDate_ACRAmount, .0000),
	CSTAmount           = ISNULL(HeaderAmountsReverseDate_CSTAmount, .0000),
	UnRecogREVAmount    = ISNULL(HeaderAmountsREVCST_UnRecogREVAmount, .0000),
	UnRecogWIPAmount    = ISNULL(HeaderAmountsCharge.UnRecogWIPAmount, .0000),
	UnRecogACRAmount    = ISNULL(HeaderAmountsCharge.UnRecogACRAmount, .0000),
	UnRecogCSTAmount    = ISNULL(HeaderAmountsREVCST_UnRecogCSTAmount, .0000),

	ColoadMaster   = ColoadMaster.JS_UniqueConsignRef,
	IsColoadMaster = CASE WHEN JS.JS_ShipmentType in ('CLD', 'CLB', 'BCN', 'ASM') THEN 'Y' ELSE 'N' END,

	JobRecognitionDate = ISNULL(RecognitionDates.DateList, ''),

	JobStatus                           = JH_Status,
	JobCreatedDate                      = JH_SystemCreateTimeUtc,
	JobOverseasAgentCode                = OverseasAgentOrgHeader.OH_Code,
	JobOverseasAgentName                = OverseasAgentOrgHeader.OH_FullName,
	OverseasAgentARSettlementGroupCode  = OverseasAgentARSettleGroupOrgHeader.OH_Code,
	OverseasAgentARSettlementGroupName  = OverseasAgentARSettleGroupOrgHeader.OH_FullName,

	SalesRepPK       = SalesRep.GS_PK,
	SalesRepName     = SalesRep.GS_FullName,
	OperatorPK       = Operator.GS_PK,
	OperatorName     = Operator.GS_FullName,

	ImportBrokerCode = Importer.OH_Code,
	ImportBrokerName = Importer.OH_FullName,
	ExportBrokerCode = Exporter.OH_Code,
	ExportBrokerName = Exporter.OH_FullName,

	TEU            = Containers.TotalTEU,
	ContainerCount = Containers.ContainerCount,
	CountOther     = Containers.CountOther,
	Count1         = Containers.Count1,
	Count2         = Containers.Count2,
	Count3         = Containers.Count3,
	Count4         = Containers.Count4,
	Count5         = Containers.Count5,
	Count6         = Containers.Count6,
	Count7         = Containers.Count7,
	Count8         = Containers.Count8,
	Count9         = Containers.Count9,
	Count10        = Containers.Count10,
	Count11        = Containers.Count11,
	Count12        = Containers.Count12,
	Count13        = Containers.Count13,
	Count14        = Containers.Count14,
	Count15        = Containers.Count15,

	JW_RL_NKLoadPortFirst = FirstLastConsolTransport.FirstLoad_Port,
	JW_ETDFirst           = FirstLastConsolTransport.FirstLoad_ETD,
	JW_RL_NKDiscPortLast  = FirstLastConsolTransport.LastDischarge_Port,
	JW_ETALast            = FirstLastConsolTransport.LastDischarge_ETA,

	CarrierCode                   = CASE WHEN Carrier.OH_Code is NULL THEN ShipmentCarrier.OH_Code ELSE Carrier.OH_Code END,
	CarrierName                   = CASE WHEN Carrier.OH_FullName is NULL THEN ShipmentCarrier.OH_FullName ELSE Carrier.OH_FullName END,

	JP_FCLPickupEquipmentNeeded   = JP_FCLPickupEquipmentNeeded,
	JP_EstimatedPickup            = JP_EstimatedPickup,
	JP_PickupRequiredBy           = JP_PickupRequiredBy,
	JP_PickupCartageAdvised       = JP_PickupCartageAdvised,
	JP_PickupCartageCompleted     = JP_PickupCartageCompleted,
	JS_InterimReceipt             = JS.JS_InterimReceipt,
	JS_A_RCV                      = JS.JS_A_RCV,
	JP_FCLDeliveryEquipmentNeeded = JP_FCLDeliveryEquipmentNeeded,
	JP_EstimatedDelivery          = JP_EstimatedDelivery,
	JP_DeliveryRequiredBy         = JP_DeliveryRequiredBy,
	JP_DeliveryCartageAdvised     = JP_DeliveryCartageAdvised,
	JP_DeliveryCartageCompleted   = JP_DeliveryCartageCompleted,
	ServiceLevelCode              = JS.JS_RS_NKServiceLevel,
	ShippersReference             = JS.JS_BookingReference

FROM
	(
		SELECT s.JS_PK, s.JS_A_RCV, s.JS_InterimReceipt, s.JS_RS_NKServiceLevel, s.JS_BookingReference, s.JS_ShipmentType, s.JS_OH_ExportBroker, s.JS_OH_ImportBroker, s.JS_JS_ColoadMasterShipment, s.JS_RL_NKOrigin, s.JS_RL_NKDestination, s.JS_Direction, s.JS_UniqueConsignRef,
				s.JS_TransportMode, s.JS_PackingMode, s.JS_INCO, s.JS_AdditionalTerms, s.JS_HouseBill, s.JS_HouseBillOfLadingType, s.JS_E_DEP, s.JS_E_ARV, s.JS_ActualWeight, s.JS_ActualVolume, s.JS_LoadingMeters, s.JS_ActualChargeable, s.JS_IsCancelled, s.JS_UnitOfWeight, s. JS_UnitOfVolume, s.JS_TotalPackageCount, s.JS_F3_NKTotalCountPackType, s.JS_OuterPacks, s.JS_F3_NKPackType, s.JS_SystemCreateTimeUtc, s.JS_GoodsDescription, s.JS_OA_BookedShippingLineAddress
		FROM
			dbo.csfn_JobShipmentWithDirection(@CurrentCountry) as s 
			LEFT JOIN
			(
				SELECT DISTINCT
					JS_JS_ColoadMasterShipment
				FROM
					dbo.JobShipment 
				WHERE
					JS_JS_ColoadMasterShipment is NOT NULL
					AND (@CoLoadType = 'SUB' OR @CoLoadType = 'STA')
			) AS s2 ON s2.JS_JS_ColoadMasterShipment = s.JS_PK AND (@CoLoadType = 'SUB' OR @CoLoadType = 'STA' AND s.JS_JS_ColoadMasterShipment is NULL)
		WHERE
			(
				@CoLoadType = 'ALL'
				OR @CoLoadType = 'MAS' AND s.JS_JS_ColoadMasterShipment is NULL
				OR @CoLoadType = 'SUB' AND s2.JS_JS_ColoadMasterShipment is NULL
				OR @CoLoadType = 'STA' AND s.JS_JS_ColoadMasterShipment is NULL AND s2.JS_JS_ColoadMasterShipment is NULL
			)
			AND JS_IsForwardRegistered = 1
			AND (@IncludeInactive = 'Y' OR JS_IsCancelled = 0)
	) AS JS

	LEFT JOIN ShipmentEntryNumbers AS CusNums ON CusNums.JS = JS.JS_PK

	LEFT JOIN dbo.csfn_ShipmentMainConsol(@CurrentCountry) AS ShipmentConsolLink ON ShipmentConsolLink.JS_PK = JS.JS_PK 

	LEFT JOIN dbo.JobConsol AS Consol ON Consol.JK_PK = ShipmentConsolLink.JK_PK 

	LEFT JOIN dbo.ctfn_JobShipmentOrg('CRD') AS Consignor ON Consignor.JS_PK = JS.JS_PK 
	LEFT JOIN dbo.ctfn_JobShipmentOrg('CED') AS Consignee ON Consignee.JS_PK = JS.JS_PK 
	LEFT JOIN dbo.ctfn_JobShipmentOrg('SCP') AS ControllingCustomer ON ControllingCustomer.JS_PK = JS.JS_PK 
	LEFT JOIN dbo.ctfn_JobShipmentOrg('CAG') AS ControllingAgent ON ControllingAgent.JS_PK = JS.JS_PK 

	LEFT JOIN
	(
		SELECT
			JE_JS
		FROM
			dbo.JobDeclaration 
		WHERE
			JE_GB IN (SELECT GB_PK FROM dbo.GlbBranch WHERE GB_GC = @CompanyPK) 
		GROUP BY
			JE_JS
	) AS JobDeclaration ON JE_JS = JS.JS_PK

	LEFT JOIN dbo.OrgAddress AS CarrierAddress ON CarrierAddress.OA_PK = Consol.JK_OA_ShippingLineAddress 
	LEFT JOIN dbo.OrgHeader  AS Carrier        ON Carrier.OH_PK = CarrierAddress.OA_OH 

	LEFT JOIN dbo.OrgAddress AS ShipmentCarrierAddress ON ShipmentCarrierAddress.OA_PK = JS.JS_OA_BookedShippingLineAddress 
	LEFT JOIN dbo.OrgHeader  AS ShipmentCarrier        ON ShipmentCarrier.OH_PK = ShipmentCarrierAddress.OA_OH 

	LEFT JOIN dbo.OrgAddress AS SendingAgentAddress ON SendingAgentAddress.OA_PK = Consol.JK_OA_SendingForwarderAddress 
	LEFT JOIN dbo.OrgHeader  AS SendingAgent        ON SendingAgent.OH_PK = SendingAgentAddress.OA_OH 

	LEFT JOIN dbo.OrgAddress AS ReceivingAgentAddress ON ReceivingAgentAddress.OA_PK = Consol.JK_OA_ReceivingForwarderAddress 
	LEFT JOIN dbo.OrgHeader  AS ReceivingAgent        ON ReceivingAgent.OH_PK = ReceivingAgentAddress.OA_OH 

	LEFT JOIN dbo.OrgAddress AS CreditorAddress ON CreditorAddress.OA_PK = Consol.JK_OA_CreditorAddress 
	LEFT JOIN dbo.OrgHeader AS CoLoad   ON CoLoad.OH_PK = CreditorAddress.OA_OH AND Consol.JK_AgentType = 'CLD'
	LEFT JOIN dbo.OrgHeader AS Exporter ON Exporter.OH_PK = JS.JS_OH_ExportBroker 
	LEFT JOIN dbo.OrgHeader AS Importer ON Importer.OH_PK = JS.JS_OH_ImportBroker 

	LEFT JOIN
	(
		SELECT
			JW_JK,
			JW_RL_NKLoadPort = MIN(JW_RL_NKLoadPort),
			JW_RL_NKDiscPort = MIN(JW_RL_NKDiscPort),
			JW_Vessel        = MIN(JW_Vessel),
			JW_VoyageFlight  = MIN(JW_VoyageFlight),
			JW_ETD           = MIN(JW_ETD),
			JW_ETA           = MIN(JW_ETA),
			JW_ATD           = MIN(JW_ATD),
			JW_ATA           = MIN(JW_ATA)
		FROM
			dbo.csfn_MainConsolTransport(@CurrentCountry) 
		GROUP BY
			JW_JK
	) AS MainConTrans ON MainConTrans.JW_JK = Consol.JK_PK

	LEFT JOIN dbo.JobHeader ON JH_GC = @CompanyPK AND JH_ParentTableCode = 'JS' AND JH_ParentID = JS.JS_PK AND JH_IsActive = 1

	LEFT JOIN 
		(
			SELECT JH = D3_JH FROM dbo.JobChargeRevRecognition 
			WHERE D3_RecognitionDate >= @JobRevFrom AND D3_RecognitionDate < @JobRevTo 
			GROUP BY D3_JH
		) AS RecognisedJobs ON JH_PK = RecognisedJobs.JH and (@JobRevFrom > '1900-01-01 00:00:00' or @JobRevTo < '2079-06-06 23:59:29')
	LEFT JOIN dbo.JobRevRecognitionDates AS RecognitionDates ON RecognitionDates.JH = JH_PK 

	LEFT JOIN AccTransactionLinesCTE ON AccTransactionLinesCTE.JH = JH_PK

	LEFT JOIN
	(
		SELECT
			JH            = JR_JH,
			UnRecogWIPAmount = SUM(CASE WHEN JR_AL_ARLine IS NULL AND @TransactionFrom = '1900-01-01 00:00:00' AND @TransactionTo = '2079-06-06 23:59:29' THEN CAST(JR_LocalSellAmt AS DECIMAL(24, 9)) ELSE 0 END),
			UnRecogACRAmount = SUM(CASE WHEN JR_AL_APLine IS NULL AND @TransactionFrom = '1900-01-01 00:00:00' AND @TransactionTo = '2079-06-06 23:59:29' THEN -CAST(JR_LocalCostAmt AS DECIMAL(24, 9)) ELSE 0 END)
		FROM
			dbo.JobCharge 
		WHERE
			(JR_LocalSellAmt != 0 AND JR_AL_ARLine IS NULL) 
			OR (JR_LocalCostAmt != 0 AND JR_AL_APLine IS NULL)
		GROUP BY
			JR_JH
	) AS HeaderAmountsCharge ON HeaderAmountsCharge.JH = JH_PK

	LEFT JOIN dbo.GlbBranch     ON GB_PK = JH_GB 
	LEFT JOIN dbo.GlbDepartment ON GE_PK = JH_GE 

	LEFT JOIN dbo.GlbStaff AS SalesRep ON SalesRep.GS_Code = JH_GS_NKRepSales 
	LEFT JOIN dbo.GlbStaff AS Operator ON Operator.GS_Code = JH_GS_NKRepOps 

	LEFT JOIN dbo.OrgAddress AS LocalClientAddress ON LocalClientAddress.OA_PK = JH_OA_LocalChargesAddr 
	LEFT JOIN dbo.OrgHeader  AS LocalClient        ON LocalClient.OH_PK = LocalClientAddress.OA_OH 

	LEFT JOIN dbo.JobDocsAndCartage ON JP_ParentID = JS.JS_PK 
	LEFT JOIN (SELECT JJ_ParentID FROM dbo.JobCartage GROUP BY JJ_ParentID) AS Cartage ON Cartage.JJ_ParentID = JS.JS_PK

	LEFT JOIN dbo.FCLShipmentContainersByConsol(@OrderedStorageClassCodesList) AS Containers ON ShipmentPK = JS.JS_PK AND ConsolPK = Consol.JK_PK 

	LEFT JOIN dbo.JobShipment AS ColoadMaster ON ColoadMaster.JS_PK = JS.JS_JS_ColoadMasterShipment 

	LEFT JOIN dbo.ViewFirstLastConsolTransport AS FirstLastConsolTransport ON FirstLastConsolTransport.ParentType = 'CON' AND FirstLastConsolTransport.JK = Consol.JK_PK 

	LEFT JOIN
	(
		SELECT
			LocoCode
		FROM
			dbo.csfn_LocoReportingZones(NULL) 
		WHERE
			ZoneCode = @Origin
		GROUP BY
			LocoCode
	) AS OriginZone ON OriginZone.LocoCode = JS.JS_RL_NKOrigin AND LEN(@Origin) = 4

	LEFT JOIN
	(
		SELECT
			LocoCode
		FROM
			dbo.csfn_LocoReportingZones(NULL) 
		WHERE
			ZoneCode = @Destination
		GROUP BY
			LocoCode
	) AS DestinationZone ON DestinationZone.LocoCode = JS.JS_RL_NKDestination AND LEN(@Destination) = 4

	LEFT JOIN dbo.OrgAddress as OverseasAgentAddress ON JobHeader.JH_OA_AgentCollectAddr = OverseasAgentAddress.OA_PK 
	LEFT JOIN dbo.OrgHeader as OverseasAgentOrgHeader ON OverseasAgentAddress.OA_OH = OverseasAgentOrgHeader.OH_PK 

	LEFT JOIN 
	(
		SELECT
			PR_OH_Parent,
			CONVERT(uniqueidentifier, MAX(CONVERT(CHAR(36), PR_OH_RelatedParty))) AS RelatedParty
		FROM
			dbo.OrgRelatedParty 
		WHERE
			(
				OrgRelatedParty.PR_PartyType = 'ARS' AND
				OrgRelatedParty.PR_GC = @CompanyPK
			)
		GROUP BY
			PR_OH_Parent
	)  AS LocalClientARSettlementGroupRelatedParty ON LocalClientARSettlementGroupRelatedParty.PR_OH_Parent = LocalClient.OH_PK

	LEFT JOIN 
	(
		SELECT
			PR_OH_Parent, 
			CONVERT(uniqueidentifier, MAX(CONVERT(CHAR(36), PR_OH_RelatedParty))) AS RelatedParty
		FROM
			dbo.OrgRelatedParty 
		WHERE
			(
				OrgRelatedParty.PR_PartyType = 'ARS' AND
				OrgRelatedParty.PR_GC = @CompanyPK
			)
		GROUP BY
			PR_OH_Parent
	)  AS OverseasAgentARSettlementGroupRelatedParty ON OverseasAgentARSettlementGroupRelatedParty.PR_OH_Parent = OverseasAgentOrgHeader.OH_PK

	LEFT JOIN dbo.OrgHeader as LocalClientARSettleGroupOrgHeader ON LocalClientARSettleGroupOrgHeader.OH_PK = LocalClientARSettlementGroupRelatedParty.RelatedParty 
	LEFT JOIN dbo.OrgHeader as OverseasAgentARSettleGroupOrgHeader ON OverseasAgentARSettleGroupOrgHeader.OH_PK = OverseasAgentARSettlementGroupRelatedParty.RelatedParty 
	
	CROSS APPLY dbo.IsUnitMetric(JS.JS_UnitOfWeight, JS.JS_UnitOfVolume) AS IsUnitMetricValue
	CROSS APPLY dbo.GetChargeableUnit(JS.JS_TransportMode, IsUnitMetricValue.Value) AS ChargeableUnitValue
	CROSS APPLY dbo.IncotermPrepaidOrCollect(JS.JS_INCO) AS IncotermDetails

WHERE
	(
		ISNULL(@Origin, '') = ''
		OR LEN(@Origin) = 5 AND @Origin = JS.JS_RL_NKOrigin
		OR LEN(@Origin) = 2 AND @Origin = LEFT(JS.JS_RL_NKOrigin, 2)
		OR LEN(@Origin) = 4 AND OriginZone.LocoCode is NOT NULL
	)
	AND
	(
		ISNULL(@Destination, '') = ''
		OR LEN(@Destination) = 5 AND @Destination = JS.JS_RL_NKDestination
		OR LEN(@Destination) = 2 AND @Destination = LEFT(JS.JS_RL_NKDestination, 2)
		OR LEN(@Destination) = 4 AND DestinationZone.LocoCode is NOT NULL
	)
	AND (@Direction = 'ALL' OR JS_Direction = @Direction)
	AND
	(
		@RelatedParty is NULL
		OR ISNULL(@RelatedClientType, '') = ''
		OR ISNULL(@RelatedPartyType, '') = ''
		OR
		(
			@RelatedClientType > '' AND @RelatedPartyType > '' AND @RelatedParty is NOT NULL
			AND
				CASE @RelatedClientType
					WHEN 'CNR' THEN Consignor.OH_PK
					WHEN 'CNE' THEN Consignee.OH_PK
					WHEN 'LCL' THEN LocalClient.OH_PK
					WHEN 'SCP' THEN ControllingCustomer.OH_PK
				END in (SELECT PR_OH_Parent FROM dbo.OrgRelatedParty WHERE PR_OH_RelatedParty = @RelatedParty AND PR_PartyType = @RelatedPartyType) 
		)
	)
	AND (@JobRevFrom ='1900-01-01 00:00:00' AND @JobRevTo = '2079-06-06 23:59:29' OR RecognisedJobs.JH IS NOT NULL)
	AND
	(
		(@TransactionFrom = '1900-01-01 00:00:00' AND @TransactionTo = '2079-06-06 23:59:29')
		OR AccTransactionLinesCTE.JH IS NOT NULL
	)
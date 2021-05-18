#Requires -version 3.0
Set-StrictMode -Version Latest

<#
**************************************************
* Private members
**************************************************
#>

. (Join-Path $PSScriptRoot 'Utilities.ps1')

Function _GetCurrentUser($Client)
{
	return $Client.GetCurrentUser();
}

Function _GetTridionUsers($Client, $IncludePredefinedUsers)
{
	$filter = New-Object Tridion.ContentManager.CoreService.Client.UsersFilterData;
	if (-not $IncludePredefinedUsers)
	{
		$filter.IsPredefined = $false;
	}
	return $Client.GetSystemWideList($filter);
}

Function _GetTridionGroups($Client)
{
	$filter = New-Object Tridion.ContentManager.CoreService.Client.GroupsFilterData;
	return $Client.GetSystemWideList($filter);
}

Function _AddPublicationScope($Group, $Scope)
{
	if ($Scope)
	{
		foreach ($publicationUri in $Scope)
		{
			$link = New-Object Tridion.ContentManager.CoreService.Client.LinkWithIsEditableToRepositoryData;
			$link.IdRef = $publicationUri;
			$Group.Scope += $link;
		}
	}
}

Function _AddGroupMembership($Trustee, $GroupUri)
{
	if (!$GroupUri) { return; }

	foreach($uri in @($GroupUri))
	{
		$groupData = New-Object Tridion.ContentManager.CoreService.Client.GroupMembershipData;
		$groupLink = New-Object Tridion.ContentManager.CoreService.Client.LinkToGroupData;
		$groupLink.IdRef = $uri;
		$groupData.Group = $groupLink;
		$Trustee.GroupMemberships += $groupData;
	}
}


<#
**************************************************
* Public members
**************************************************
#>

function Get-TridionUser
{
    <#
    .Synopsis
    Returns a list of Tridion users matching the specified criteria.

    .Description
    Gets a list of UserData objects with information about the matching users within Tridion.
    If called without any parameters, a list of all users will be returned.

    .Notes
    Example of properties available: Title, IsEnabled, LanguageId, LocaleId, Privileges (system administrator = 1), etc.
    
    For a full list, consult the Content Manager Core Service API Reference Guide documentation 
    (Tridion.ContentManager.Data.Security.UserData object)

    .Inputs
    None.

    .Outputs
    Returns an array of objects of type [Tridion.ContentManager.CoreService.Client.UserData].

    .Link
    Get the latest version of this script from the following URL:
    https://github.com/pkjaer/tridion-powershell-modules

    .Example
    Get-TridionUser | Format-List
    Returns a formatted list of properties all users in the system.

    .Example
    Get-TridionUser | Select-Object Title, LanguageId, LocaleId, Privileges
    Returns the title, language, locale, and privileges (system administrator) of each user in the system.
    
    .Example
    Get-TridionUser -Id 'tcm:0-12-65552'
    Returns information about user #12 within Tridion (typically the Administrator user created during installation).

    .Example
    Get-TridionUser -Current
    Returns information about the currently logged in user (i.e. you).

    .Example
    Get-TridionUser -Name 'COMPANY\*'
    Returns information about all users in the COMPANY domain (name starts with COMPANY\).

    .Example
    Get-TridionUser -Description 'Isaac *'
    Returns information about all users with the first name 'Isaac'.

    .Example
    Get-TridionUser -Description 'Isaac *' -ExpandProperties
    Returns all available information about all users with the first name 'Isaac'.

    .Example
    Get-TridionUser -Filter { $_.LanguageId -eq '1033' }
    Returns information about all users who are currently using English as their UI language.
    
    #>
    [CmdletBinding(DefaultParameterSetName='ByFilter')]
    Param
    (
		# Filtering script block. You can use this to filter based on any criteria.
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByFilter', Position=0)]
        [ScriptBlock]$Filter,
		
		# The TCM URI of the user to load.
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName='ById', Position=0)]
		[ValidateNotNullOrEmpty()]
        [string]$Id,

		# The name (including domain) of the user to load. Wildcards are supported.
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByTitle', Position=0)]
		[ValidateNotNullOrEmpty()]
		[Alias('Title')]
        [string]$Name,
		
		# The 'friendly' name of the user to load. Wildcards are supported.
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByDescription', Position=0)]
		[ValidateNotNullOrEmpty()]
        [string]$Description,
		
		# Only return the currently logged on user.
        [Parameter(Mandatory=$true, ParameterSetName='CurrentUser', Position=0)]
		[switch]$Current,
		
		# Load all properties for each entry in the list. By default, only some properties are loaded (for performance reasons).
		[Parameter(ParameterSetName = 'ByTitle')]
		[Parameter(ParameterSetName = 'ByDescription')]
		[Parameter(ParameterSetName = 'ByFilter')]
		[switch]$ExpandProperties
    )

	Begin
	{
		$verboseRequested = ($PSBoundParameters['Verbose'] -eq $true);
        $client = Get-TridionCoreServiceClient -Verbose:$verboseRequested;
		$userCache = $null;
		$filterScript = $null;
	}
    
    Process
    {
		switch($PsCmdlet.ParameterSetName)
		{
			'CurrentUser'
			{
				Write-Verbose "Loading current user...";
				return _GetCurrentUser $client;
			}
			
			'ById' 
			{
				$itemId = _GetIdFromInput $Id;
				if (_IsNullUri($itemId)) { return $null; }
				_AssertItemType $itemId 65552;
				
				Write-Verbose "Loading user with ID '$itemId'...";
				if (_IsExistingItem $client $itemId)
				{
					return _GetItem $client $itemId;
				}
				return $null;
			}
			
			'ByTitle'
			{
				$filterScript = { $_.Title -like $Name };
			}
			
			'ByDescription'
			{
				$filterScript = { $_.Description -like $Description };
			}
			
			'ByFilter'
			{
				$filterScript = $Filter;
			}
		}

		
		if ($userCache -eq $null)
		{
			$userCache = _GetTridionUsers $client $false;
		}
		
		$users = $userCache;
		if ($filterScript)
		{
			$users = $users | Where-Object $filterScript;
		}

		return _ExpandPropertiesIfRequested $users $ExpandProperties;
    }
	
	End
	{
		Close-TridionCoreServiceClient $client;
	}
}

function Get-TridionGroup
{
    <#
    .Synopsis
    Gets information about all groups within Tridion matching the specified criteria.

    .Description
    Gets a list of GroupData objects containing information about all Groups within Tridion matching the specified criteria.

    .Notes
    Example of properties available: Id, Title, Description, Scope, etc.
    
    For a full list, consult the Content Manager Core Service API Reference Guide documentation 
    (Tridion.ContentManager.Data.Security.GroupData object)

    .Inputs
    None.

    .Outputs
    Returns a list of objects of type [Tridion.ContentManager.CoreService.Client.GroupData].

    .Link
    Get the latest version of this script from the following URL:
    https://github.com/pkjaer/tridion-powershell-modules
	
	.Example
    Get-TridionGroup
    Returns information about all Groups in the system.
	
	.Example
    Get-TridionGroup -Id 'tcm:0-7-65568'
    Returns information about the Group with the ID 'tcm:0-7-65568'.

    .Example
    Get-TridionGroup -Title 'Editor'
    Returns information about the Group named 'Editor'.
    
    #>
    [CmdletBinding(DefaultParameterSetName='ByFilter')]
    Param
    (
		# Filtering script block. You can use this to filter based on any criteria.
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByFilter', Position=0)]
        [ScriptBlock]$Filter,
		
		# The TCM URI of the Group to load.
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName='ById', Position=0)]
		[ValidateNotNullOrEmpty()]
        [string]$Id,

		# The (partial) name of the Group(s) to load. Wildcards are supported.
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByTitle', Position=0)]
		[ValidateNotNullOrEmpty()]
		[Alias('Title')]
        [string]$Name,
		
		# The Description of the Group to load. Wildcards are supported.
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByDescription', Position=0)]
		[ValidateNotNullOrEmpty()]
        [string]$Description,
		
		# Load all properties for each entry in the list. By default, only some properties are loaded (for performance reasons).
		[Parameter(ParameterSetName = 'ByTitle')]
		[Parameter(ParameterSetName = 'ByDescription')]
		[Parameter(ParameterSetName = 'ByFilter')]
		[switch]$ExpandProperties
    )
	
	Begin
	{
		$verboseRequested = ($PSBoundParameters['Verbose'] -eq $true);
        $client = Get-TridionCoreServiceClient -Verbose:$verboseRequested;
		$groupCache = $null;
		$filterScript = $null;
	}
    
    Process
    {
		switch($PsCmdlet.ParameterSetName)
		{
			'ById' 
			{
				$itemId = _GetIdFromInput $Id;
				if (_IsNullUri($itemId)) { return $null; }
				_AssertItemType $itemId 65568;
				
				if (_IsExistingItem $client $itemId)
				{
					return _GetItem $client $itemId;
				}
				return $null;
			}
			
			'ByTitle'
			{
				$filterScript = { $_.Title -like $Name };
			}
			
			'ByDescription'
			{
				$filterScript = { $_.Description -like $Description };
			}
			
			'ByFilter'
			{
				$filterScript = $Filter;
			}
		}

		
		if ($groupCache -eq $null)
		{
			$groupCache = _GetTridionGroups $client;
		}
		
		$list = $groupCache;
		if ($filterScript)
		{
			$list = $list | Where-Object $filterScript;
		}

		return _ExpandPropertiesIfRequested $list $ExpandProperties;
    }
	
	End
	{
		Close-TridionCoreServiceClient $client;
	}
}

function New-TridionGroup
{
    <#
    .Synopsis
    Adds a new Group to Tridion Content Manager.

    .Description
    Adds a new Group to Tridion Content Manager with the given name. 
    Optionally, you may specify a description for the Group. 
	It can also be a member of other Groups and only be available under specific Publications.

    .Notes
    Example of properties available: Id, Title, Scope, GroupMemberships, etc.
    
    For a full list, consult the Content Manager Core Service API Reference Guide documentation 
    (Tridion.ContentManager.Data.Security.GroupData object)

    .Inputs
    [string] Name: the user name including the domain.
    [string] Description: a description of the Group. Defaults to the $Name parameter.

    .Outputs
    Returns an object of type [Tridion.ContentManager.CoreService.Client.GroupData], representing the newly created Group.

    .Link
    Get the latest version of this script from the following URL:
    https://github.com/pkjaer/tridion-powershell-modules

    .Example
    New-TridionGroup -Name "Content Editors (NL)"
    Creates a new Group with the name "Content Editors (NL)". It is valid for all Publications.
    
    .Example
    New-TridionGroup -Name "Content Editors (NL)" -Description "Dutch Content Editors"
    Creates a new Group with the name "Content Editors (NL)" and a description of "Dutch Content Editors". 
	It is valid for all Publications.
    
    .Example
    New-TridionGroup -Name "Content Editors (NL)" -Description "Dutch Content Editors" | Format-List
    Creates a new Group with the name "Content Editors (NL)" and a description of "Dutch Content Editors". 
	It is valid for all Publications.
    Displays all of the properties of the resulting Group as a list.
	
	.Example
	New-TridionGroup -Name "Content Editors (NL)" -Description "Dutch Content Editors" -Scope @("tcm:0-1-1", "tcm:0-2-1") -MemberOf @("tcm:0-5-65568", "tcm:0-7-65568");
	Creates a new Group with the name "Content Editors (NL)" and a description of "Dutch Content Editors". 
	It is only usable in Publication 1 and 2.
	It is a member of the Author and Editor groups.    
	
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
			# The name of the new Group. This is displayed to end-users.
            [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
			[ValidateNotNullOrEmpty()]
			[Alias('Title')]
            [string]$Name,
            
			# The description of the new Group. Generally used to indicate the purpose of the group. 
            [Parameter(ValueFromPipelineByPropertyName=$true)]
            [string]$Description,
			
			# A list of URIs for the Publications in which the new Group applies.
			[Parameter(ValueFromPipelineByPropertyName=$true)]
			[string[]]$Scope,
			
			# A list of URIs for the existing Groups that the new Group should be a part of.
			[Parameter(ValueFromPipelineByPropertyName=$true)]
			[string[]]$MemberOf
    )
	
	Begin
	{
        $client = Get-TridionCoreServiceClient -Verbose:($PSBoundParameters['Verbose'] -eq $true);
	}

    Process
    {
        if ($client -ne $null)
        {
			$groupDescription = _GetPropertyFromInput $Description 'Description';
			if (!$groupDescription) { $groupDescription = $Name; }

			$group = _GetDefaultData $client 65568 $null $Name;
			$group.Description = $groupDescription;
			
			_AddPublicationScope $group $Scope;
			_AddGroupMembership $group $MemberOf;
			
			if ($PSCmdLet.ShouldProcess("Group { Name: '$($group.Title)', Description: '$($group.Description)' }", "Create")) 
			{
				$result = _SaveItem $client $group $true;
				return $result;
			}
        }
    }
	
	End
	{
		Close-TridionCoreServiceClient $client;
	}	
}


function New-TridionUser
{
    <#
    .Synopsis
    Adds a new user to Tridion Content Manager.

    .Description
    Adds a new user to Tridion Content Manager with the given user name and description (friendly name). 
    Optionally, the user can be given system administrator rights with the Content Manager.

    .Notes
    Example of properties available: Id, Title, Key, PublicationPath, PublicationUrl, MultimediaUrl, etc.
    
    For a full list, consult the Content Manager Core Service API Reference Guide documentation 
    (Tridion.ContentManager.Data.CommunicationManagement.PublicationData object)

    .Inputs
    [string] Name: the user name including the domain.
    [string] Description: the friendly name of the user, typically the full name. Defaults to the $Name parameter.
	[string] MemberOf: the groups you want the user to be in.
    [switch] MakeAdministrator: include this switch if you wish to give the new user full administrator rights within the Content Manager.

    .Outputs
    Returns an object of type [Tridion.ContentManager.CoreService.Client.UserData], representing the newly created user.

    .Link
    Get the latest version of this script from the following URL:
    https://github.com/pkjaer/tridion-powershell-modules

    .Example
    New-TridionUser -Name "GLOBAL\user01"
    Adds "GLOBAL\user01" to the Content Manager with a description matching the user name and no administrator rights.
	
	.Example
    New-TridionUser -Name "GLOBAL\user01" -MemberOf SuperUsers,WebMasters
    Adds "GLOBAL\user01" to the Content Manager with a description matching the user name, to groups SuperUsers and WebMasters, and with no administrator rights.
	
	.Example
    New-TridionUser -Name "GLOBAL\user01" -MemberOf "tcm:0-188-65552"
    Adds "GLOBAL\user01" to the Content Manager with a description matching the user name, to group with id tcm:0-188-65552, and with no administrator rights.
    
    .Example
    New-TridionUser -Name "GLOBAL\user01" -Description "User 01"
    Adds "GLOBAL\user01" to the Content Manager with a description of "User 01" and no administrator rights.
    
    .Example
    New-TridionUser -Name GLOBAL\User01 -MakeAdministrator
    Adds "GLOBAL\user01" to the Content Manager with a description matching the user name and system administrator rights.

    .Example
    New-TridionUser -Name "GLOBAL\user01" -Description "User 01" -MakeAdministrator | Format-List
    Adds "GLOBAL\user01" to the Content Manager with a description of "User 01" and system administrator rights.
    Displays all of the properties of the resulting user as a list.
    
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
			# The username (including domain) of the new User
            [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
			[ValidateNotNullOrEmpty()]
			[Alias('UserName')]
            [string]$Name,
			
            # The description (or 'friendly name') of the user. This is displayed throughout the UI.
            [Parameter(ValueFromPipelineByPropertyName=$true)]
            [string]$Description,
			
			# A list of URIs for the existing Groups that the new User should be a part of. Supports also Titles of the groups.
            [Parameter(ValueFromPipelineByPropertyName=$true)]
            [string[]]$MemberOf,
			
            # If set, the new user will have system administrator privileges. Use with caution.
            [Parameter(ValueFromPipelineByPropertyName=$true)]
            [switch]$MakeAdministrator
    )
	
	Begin
	{
        $client = Get-TridionCoreServiceClient -Verbose:($PSBoundParameters['Verbose'] -eq $true);
		$groupCache = $null;
	}

    Process
    {
        if ($client -ne $null)
        {
			$userDescription = _GetPropertyFromInput $Description 'Description';
			if (!$userDescription) { $userDescription = $Name; }

			$user = _GetDefaultData $client 65552 $null $Name;
			$user.Description = $userDescription;
			
			if ($MemberOf)
			{
				foreach($groupUri in $MemberOf)
				{
					if ($groupUri)
					{
						if (-not $groupUri.StartsWith('tcm:'))
						{
							# It's not a URI, it's a name. Look up the group URI by its title.
							if ($groupCache -eq $null)
							{
								$groupCache = Get-TridionGroups;
							}
							
							$group = $groupCache | Where-Object {$_.Title -eq $groupUri} | Select-Object -First 1;
							if (-not $group) 
							{
								Write-Error "Could not find a group named $groupUri.";
								continue;
							}
							
							$groupUri = $group.id;
						}
						
						_AddGroupMembership $user $groupUri;
					}
				}
			}
			
			if ($MakeAdministrator)
			{
				$user.Privileges = 1;
				# TODO: In Web 8 you need to add the user to the sys admin group instead
			}
			
			if ($PSCmdLet.ShouldProcess("User { Name: '$($user.Title)', Description: '$($user.Description)', Administrator: $MakeAdministrator }", "Create")) 
			{
				return _SaveItem $client $user $true;
			}
        }
    }
	
	End
	{
		Close-TridionCoreServiceClient $client;
	}	
}


function Disable-TridionUser
{
    <#
    .Synopsis
    Disables the specified user in Tridion Content Manager.

    .Description
    Disables the specified user in Tridion Content Manager, preventing the user from logging in or performing any actions.
    This action lasts until Enable-TridionUser is called or the user is explicitly enabled by other means (such as within the CME).

    .Inputs
    [string] Id: the TCM URI of the user.
	OR
	[Tridion.ContentManager.CoreService.Client.UserData] User: The already-loaded User object. Mostly used when using the pipeline (results from previous command).

    .Link
    Get the latest version of this script from the following URL:
    https://github.com/pkjaer/tridion-powershell-modules

    .Example
    Disable-TridionUser -User "tcm:0-25-65552"
    Disables the user with ID 'tcm:0-25-65552', preventing them from accessing the Tridion Content Manager.
	
	.Example
	Get-TridionUsers | where {$_.Description.StartsWith('Peter ') } | Disable-TridionUser
	Disables all users with the first name 'Peter'.
	
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low', DefaultParameterSetName='ById')]
    Param(
			# The user to disable, either the TCM URI or the user object itself
            [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
			[Alias('Id')]
            $User,

			[Parameter()]
			[switch]$PassThru
    )
	
	Begin
	{
        $client = Get-TridionCoreServiceClient -Verbose:($PSBoundParameters['Verbose'] -eq $true);
	}

    Process
    {
        if ($client -eq $null) { return; }

		$userObject = $User;

		if (($User -is [string]) -or ($User -is [object] -and $User.GetType().Name -ne 'UserData'))
		{
			$itemId = _GetIdFromInput $User;
			if (_IsNullUri($itemId)) { return; }
			_AssertItemType $itemId 65552;
				
			$userObject = _GetItem $client $itemId;
		}
		
		if (!$userObject) { return; }
		if ($PSCmdLet.ShouldProcess("User { Name: '$($userObject.Title)', Description: '$($userObject.Description)' }", "Disable")) 
		{
			$userObject.IsEnabled = $false;
			$result = _SaveItem $client $userObject $false;
			if ($PassThru) { return $result; }
		}
    }
	
	End
	{
		Close-TridionCoreServiceClient $client;
	}	
}


function Enable-TridionUser
{
    <#
    .Synopsis
    Enables the specified user in Tridion Content Manager.

    .Description
    Enables the specified user in Tridion Content Manager, after he or she has previously been disabled.

    .Inputs
    [string] Id: the TCM URI of the user.
	OR
	[Tridion.ContentManager.CoreService.Client.UserData] User: The already-loaded User object. Mostly used when using the pipeline (results from previous command).

    .Link
    Get the latest version of this script from the following URL:
    https://github.com/pkjaer/tridion-powershell-modules

    .Example
    Enable-TridionUser -Id "tcm:0-25-65552"
    Re-enables the user with ID 'tcm:0-25-65552'.
	
	.Example
	Get-TridionUsers | where {$_.Description.StartsWith('Peter ') } | Enable-TridionUser
	Re-enables all users with the first name 'Peter'.
	
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low', DefaultParameterSetName='ById')]
    Param(
			# The TCM URI of the user to enable
            [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName='ById')]
			[ValidateNotNullOrEmpty()]
            [string]$Id,

			# The User object of the user to enable
            [Parameter(Mandatory=$true, ValueFromPipeline=$true, ParameterSetName='WithObject')]
			[ValidateNotNull()]
            $User,

			[Parameter()]
			[switch]$PassThru
    )
	
	Begin
	{
        $client = Get-TridionCoreServiceClient -Verbose:($PSBoundParameters['Verbose'] -eq $true);
	}

    Process
    {
        if ($client -eq $null) { return; }
        
		switch($PsCmdlet.ParameterSetName)
		{
			'ById' 
			{ 
				$itemId = _GetIdFromInput $Id;
				if (_IsNullUri($itemId)) { return; }
				_AssertItemType $itemId 65552;
				
				$user = _GetItem $client $itemId;
			}

			'WithObject' 
			{
				$user = $User;
			}
		}
		
		if ($user -eq $null) { return; }
		if ($PSCmdLet.ShouldProcess("User { Name: '$($user.Title)', Description: '$($user.Description)' }", "Enable"))
		{
			$user.IsEnabled = $true;
			$result = _SaveItem $client $user $false;
			if ($PassThru) { return $result; }
		}
    }
	
	End
	{
		Close-TridionCoreServiceClient $client;
	}
}


<#
**************************************************
* Export statements
**************************************************
#>
Set-Alias -Name Get-TridionUsers -Value Get-TridionUser
Set-Alias -Name Get-TridionGroups -Value Get-TridionGroup

Export-ModuleMember -Function Get-Tridion*, New-Tridion*, Disable-Tridion*, Enable-Tridion* -Alias *
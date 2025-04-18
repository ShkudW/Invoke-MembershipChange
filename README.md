# Invoke-MembershipChange


A simple tool to add/delete a group form with the 'AccessDecision' attribute and Visibility-Public attribute

The tool supports adding to a single group or adding to multiple groups.

All you need to do is enter the refreshtoken into the tool.



```powershell.exe

Invoke-MembershipChange -RefreshToken $refreshtoken -GroupIdsInput xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxx -Action add

```

```powershell.exe

Invoke-MembershipChange -RefreshToken $refreshtoken -GroupIdsInput .\groupids.txt -Action add

```

The tool can handle rate limit 429 messages, with error message 400 - when the user is already a member of the group,
And to tool can automatically renew the access token every 7 minutes.

The tool will save all the groups you have successfully joined in a file -> success_log.txt

For removing yourself from groups:

```powershell.exe

Invoke-MembershipChange -RefreshToken $refreshtoken -GroupIdsInput .\success_log.txt -Action delete

```


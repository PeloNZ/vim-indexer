"=============================================================================
" File:        indexer.vim
" Author:      Dmitry Frank (dimon.frank@gmail.com)
" Last Change: 11 Dec 2010
" Version:     3.00 pre-beta
"=============================================================================
" See documentation in accompanying help file
" You may use this code in whatever way you see fit.

"TODO:
"
" ----------------
"  In 3.0
"
" Опцию типа "менять рабочую директорию при смене проекта", и менять ее только
" в том случае, если проект сменили, а не только файл.
"
" Перезагрузка проектов при сохранении файлов .vimprojects или .indexer_files
"
" Выяснить, почему если открыть .vimprj/my.vim, а потом открыть файл из проекта,
" то ничего не индексируется
"
" ----------------
"
" *) !!! Unsorted tags file is BAD. Please try to make SED work with sorted
"    tags file.
"
" *) test on paths with spaces, both on Linux and Windows
" *) test with one .vimprojects and .indexer_files file, define projectName
" *) rename indexer_ctagsDontSpecifyFilesIfPossible to indexer_ctagsUseDirs or
"    something
" *) make #pragma_index_none,
"         #pragma_index_dir,
"         #pragma_index_files
" *) ability to define one file in .indexer_files
" *) maybe checking whether or not ctags is version 5.8.1
" *) maybe checking whether or not sed is present
" *) maybe checking whether or not sed is correctly parsing ( \\\\ or \\ )
"

" ************************************************************************************************
"                                   ADDITIONAL FUNCTIONS
" ************************************************************************************************

" Basic background task running is different on each platform
if has("win32")
   " Works in Windows (Win7 x64)
   function! <SID>IndexerAsync_Impl(tool_cmd, vim_cmd)
      let l:cmd = a:tool_cmd

      if !empty(a:vim_cmd)
         let l:cmd .= " & ".a:vim_cmd
      endif

      silent exec "!start /MIN cmd /c \"".l:cmd."\""
   endfunction
else
   " Works in linux (Ubuntu 10.04)
   function! <SID>IndexerAsync_Impl(tool_cmd, vim_cmd)

      let l:cmd = a:tool_cmd

      if !empty(a:vim_cmd)
         let l:cmd .= " ; ".a:vim_cmd
      endif

      silent exec "! (".l:cmd.") &"
   endfunction
endif

function! <SID>IndexerAsyncCommand(command, vim_func)
   " String together and execute.
   let temp_file = tempname()

   " Grab output and error in case there's something we should see
   let tool_cmd = a:command . printf(&shellredir, temp_file)

   let vim_cmd = ""
   if !empty(a:vim_func)
      let vim_cmd = "vim --servername ".v:servername." --remote-expr \"" . a:vim_func . "('" . temp_file . "')\" "
   endif

   call <SID>IndexerAsync_Impl(tool_cmd, vim_cmd)
endfunction


function! <SID>NeedSkipBuffer(buf)
   if !empty(getbufvar(a:buf, "&buftype"))
      return 1
   endif

   if empty(bufname(a:buf))
      return 1
   endif

   if empty(getbufvar(a:buf, "&swapfile"))
      return 1
   endif

   return 0
endfunction

function! <SID>IsBufChanged()
    return (s:curFileNum != bufnr('%'))
endfunction

function! <SID>SetCurrentFile()
   if (exists("s:dFiles[".bufnr('%')."]"))
      let s:curFileNum = bufnr('%')
   else
      let s:curFileNum = 0
   endif
   let s:curVimprjKey = s:dFiles[ s:curFileNum ].sVimprjKey
endfunction

function! <SID>AddCurrentFile(sVimprjKey)
   let s:dFiles[ bufnr('%') ] = {'sVimprjKey' : a:sVimprjKey, 'projects': []}
   call <SID>SetCurrentFile()
endfunction

function! <SID>AddNewProjectToCurFile(sProjFileKey, sProjName)
   call add(s:dFiles[ s:curFileNum ].projects, {"file" : a:sProjFileKey, "name" : a:sProjName})
endfunction

function! <SID>GetKeyFromPath(sPath)
   return substitute(a:sPath, '[^a-zA-Z0-9_]', '_', 'g')
endfunction

" добавляет новый vimprj root, заполняет его текущими параметрами
function! <SID>AddNewVimprjRoot(sKey, sPath, sCdPath)
   let g:indexer_useDirsInsteadOfFiles = g:indexer_ctagsDontSpecifyFilesIfPossible

   if (!exists("s:dVimprjRoots['".a:sKey."']"))
      let s:dVimprjRoots[a:sKey] = {}
      let s:dVimprjRoots[a:sKey]["cd_path"] = a:sCdPath
      let s:dVimprjRoots[a:sKey]["proj_root"] = a:sPath
      if (!empty(a:sPath))
         let s:dVimprjRoots[a:sKey]["path"] = a:sPath.'/'.g:indexer_dirNameForSearch
      else
         let s:dVimprjRoots[a:sKey]["path"] = ""
      endif
      let s:dVimprjRoots[a:sKey]["indexerListFilename"]           = g:indexer_indexerListFilename
      let s:dVimprjRoots[a:sKey]["projectsSettingsFilename"]       = g:indexer_projectsSettingsFilename
      let s:dVimprjRoots[a:sKey]["projectName"]                   = g:indexer_projectName
      let s:dVimprjRoots[a:sKey]["enableWhenProjectDirFound"]     = g:indexer_enableWhenProjectDirFound
      let s:dVimprjRoots[a:sKey]["ctagsCommandLineOptions"]       = g:indexer_ctagsCommandLineOptions
      let s:dVimprjRoots[a:sKey]["ctagsJustAppendTagsAtFileSave"] = g:indexer_ctagsJustAppendTagsAtFileSave
      let s:dVimprjRoots[a:sKey]["useDirsInsteadOfFiles"]         = g:indexer_useDirsInsteadOfFiles
      let s:dVimprjRoots[a:sKey]["mode"]                          = ""

   endif
endfunction

function! <SID>IndexerFilesList()
   echo "* Files indexed: ".join(s:dParseGlobal.files, ', ')
endfunction

" concatenates two lists preventing duplicates
function! <SID>ConcatLists(lExistingList, lAddingList)
   let l:lResList = a:lExistingList
   for l:sItem in a:lAddingList
      if (index(l:lResList, l:sItem) == -1)
         call add(l:lResList, l:sItem)
      endif
   endfor
   return l:lResList
endfunction

" <SID>ParsePath(sPath)
"   changing '\' to '/' or vice versa depending on OS (MS Windows or not) also calls simplify()
function! <SID>ParsePath(sPath)
   if (has('win32') || has('win64'))
      let l:sPath = substitute(a:sPath, '/', '\', 'g')
   else
      let l:sPath = substitute(a:sPath, '\', '/', 'g')
   endif
   let l:sPath = simplify(l:sPath)

   " removing last "/" or "\"
   let l:sLastSymb = strpart(l:sPath, (strlen(l:sPath) - 1), 1)
   if (l:sLastSymb == '/' || l:sLastSymb == '\')
      let l:sPath = strpart(l:sPath, 0, (strlen(l:sPath) - 1))
   endif
   return l:sPath
endfunction

" <SID>Trim(sString)
" trims spaces from begin and end of string
function! <SID>Trim(sString)
   return substitute(substitute(a:sString, '^\s\+', '', ''), '\s\+$', '', '')
endfunction

" <SID>IsAbsolutePath(path) <<<
"   this function from project.vim is written by Aric Blumer.
"   Returns true if filename has an absolute path.
function! <SID>IsAbsolutePath(path)
   if a:path =~ '^ftp:' || a:path =~ '^rcp:' || a:path =~ '^scp:' || a:path =~ '^http:'
      return 2
   endif
   let path=expand(a:path) " Expand any environment variables that might be in the path
   if path[0] == '/' || path[0] == '~' || path[0] == '\\' || path[1] == ':'
      return 1
   endif
   return 0
endfunction " >>>

" returns whether or not file exists in list
function! <SID>IsFileExistsInList(aList, sFilename)
   let l:sFilename = <SID>ParsePath(a:sFilename)
   if (index(a:aList, l:sFilename, 0, 1)) >= 0
      return 1
   endif
   return 0
endfunction





function! <SID>IndexerInfo()

   let l:sProjects = ""
   let l:sPathsRoot = ""
   let l:sPathsForCtags = ""
   let l:iFilesCnt = 0
   let l:iFilesNotFoundCnt = 0

   for l:lProjects in s:dFiles[ s:curFileNum ]["projects"]
      let l:dCurProject = s:dProjFilesParsed[ l:lProjects.file ]["projects"][ l:lProjects.name ]

      if !empty(l:sProjects)
         let l:sProjects .= ", "
      endif
      let l:sProjects .= l:lProjects.name

      if !empty(l:sPathsRoot)
         let l:sPathsRoot .= ", "
      endif
      let l:sPathsRoot .= join(l:dCurProject.pathsRoot, ', ')

      if !empty(l:sPathsForCtags)
          let l:sPathsForCtags .= ", "
      endif
      let l:sPathsForCtags .= join(l:dCurProject.pathsForCtags, ', ')
      let l:iFilesCnt += len(l:dCurProject.files)
      let l:iFilesNotFoundCnt += len(l:dCurProject.not_exist)

   endfor

   if (s:dVimprjRoots[ s:curVimprjKey ].mode == '')
      echo '* Filelist: not found'
   elseif (s:dVimprjRoots[ s:curVimprjKey ].mode == 'IndexerFile')
      echo '* Filelist: indexer file: '.s:dVimprjRoots[ s:curVimprjKey ].indexerListFilename
   elseif (s:dVimprjRoots[ s:curVimprjKey ].mode == 'ProjectFile')
      echo '* Filelist: project file: '.s:dVimprjRoots[ s:curVimprjKey ].projectsSettingsFilename
   else
      echo '* Filelist: Unknown'
   endif
   if (s:dVimprjRoots[ s:curVimprjKey ].useDirsInsteadOfFiles)
      echo '* Index-mode: DIRS. (option g:indexer_ctagsDontSpecifyFilesIfPossible is ON)'
   else
      echo '* Index-mode: FILES. (option g:indexer_ctagsDontSpecifyFilesIfPossible is OFF)'
   endif
   echo '* When saving file: '.(s:dVimprjRoots[ s:curVimprjKey ].ctagsJustAppendTagsAtFileSave ? (g:indexer_useSedWhenAppend ? 'remove tags for saved file by SED, and ' : '').'just append tags' : 'rebuild tags for whole project')
   echo '* Projects indexed: '.l:sProjects
   if (!s:dVimprjRoots[ s:curVimprjKey ].useDirsInsteadOfFiles)
      echo "* Files indexed: there's ".l:iFilesCnt.' files.' 
      " Type :IndexerFiles to list'
      echo "* Files not found: there's ".l:iFilesNotFoundCnt.' non-existing files. ' 
      ".join(s:dParseGlobal.not_exist, ', ')
   endif

   echo "* Root paths: ".l:sPathsRoot
   echo "* Paths for ctags: ".l:sPathsForCtags

   echo '* Paths (with all subfolders): '.&path
   echo '* Tags file: '.&tags
   echo '* Project root: '.($INDEXER_PROJECT_ROOT != '' ? $INDEXER_PROJECT_ROOT : 'not found').'  (Project root is a directory which contains "'.g:indexer_dirNameForSearch.'" directory)'
endfunction




" ************************************************************************************************
"                                   CTAGS UNIVERSAL FUNCTIONS
" ************************************************************************************************

" generates command to call ctags apparently params.
" params:
"   dParams {
"      append,    // 1 or 0
"      recursive, // 1 or 0
"      sTagsFile, // ".."
"      sFiles,    // ".."
"   }
function! <SID>GetCtagsCommand(dParams)
   let l:sAppendCode = ''
   let l:sRecurseCode = ''

   if (a:dParams.append)
      let l:sAppendCode = '-a'
   endif

   if (a:dParams.recursive)
      let l:sRecurseCode = '-R'
   endif

   " when using append without Sed we SHOULD use sort, because of if there's no sort, then
   " symbols will be doubled.
   "
   " when using append with Sed we SHOULD NOT use sort, because of if there's sort, then
   " tags file becomes damaged, i can't figure out why.
   " TODO: very need to make sed work with sorted files too, because of 
   "       Vim works much longer with unsorted file.
   "
   if (s:dVimprjRoots[ s:curVimprjKey ].ctagsJustAppendTagsAtFileSave && g:indexer_useSedWhenAppend)
      let l:sSortCode = '--sort=no'
   else
      let l:sSortCode = '--sort=yes'
   endif

   let l:sTagsFile = '"'.a:dParams.sTagsFile.'"'
   if (has('win32') || has('win64'))
      let l:sCmd = 'ctags -f '.l:sTagsFile.' '.l:sRecurseCode.' '.l:sAppendCode.' '.l:sSortCode.' '.s:dVimprjRoots[ s:curVimprjKey ].ctagsCommandLineOptions.' '.a:dParams.sFiles
   else
      let l:sCmd = 'ctags -f '.l:sTagsFile.' '.l:sRecurseCode.' '.l:sAppendCode.' '.l:sSortCode.' '.s:dVimprjRoots[ s:curVimprjKey ].ctagsCommandLineOptions.' '.a:dParams.sFiles.' &'
   endif
   return l:sCmd
endfunction

" executes ctags called with specified params.
" params look in comments to <SID>GetCtagsCommand()
function! <SID>ExecCtags(dParams)
   let l:sCmd = <SID>GetCtagsCommand(a:dParams)

   call <SID>IndexerAsyncCommand(l:sCmd, "")
   "if exists("*AsyncCommand")
      "call AsyncCommand(l:sCmd, "")
   "else
      "let l:resp = system(l:sCmd)
   "endif
endfunction


" builds list of files (or dirs) and executes Ctags.
" If list is too long (if command is more that g:indexer_maxOSCommandLen)
" then executes ctags several times.
" params:
"   dParams {
"      lFilelist, // [..]
"      sTagsFile, // ".."
"      recursive  // 1 or 0
"   }
function! <SID>ExecCtagsForListOfFiles(dParams)

   " we need to know length of command to call ctags (without any files)
   let l:sCmd = <SID>GetCtagsCommand({'append': 1, 'recursive': a:dParams.recursive, 'sTagsFile': a:dParams.sTagsFile, 'sFiles': ""})
   let l:iCmdLen = strlen(l:sCmd)


   " now enumerating files
   let l:sFiles = ''
   for l:sCurFile in a:dParams.lFilelist

      let l:sCurFile = <SID>ParsePath(l:sCurFile)
      " if command with next file will be too long, then executing command
      " BEFORE than appending next file to list
      if ((strlen(l:sFiles) + strlen(l:sCurFile) + l:iCmdLen) > g:indexer_maxOSCommandLen)
         call <SID>ExecCtags({'append': 1, 'recursive': a:dParams.recursive, 'sTagsFile': a:dParams.sTagsFile, 'sFiles': l:sFiles})
         let l:sFiles = ''
      endif

      let l:sFiles = l:sFiles.' "'.l:sCurFile.'"'
   endfor

   if (l:sFiles != '')
      call <SID>ExecCtags({'append': 1, 'recursive': a:dParams.recursive, 'sTagsFile': a:dParams.sTagsFile, 'sFiles': l:sFiles})
   endif

endfunction


function! <SID>ExecSed(dParams)
   " linux: all should work
   " windows: cygwin works, non-cygwin needs \\ instead of \\\\
   let l:sFilenameToDeleteTagsWith = a:dParams.sFilenameToDeleteTagsWith
   let l:sFilenameToDeleteTagsWith = substitute(l:sFilenameToDeleteTagsWith, "\\\\", "\\\\\\\\\\\\\\\\", "g")
   let l:sFilenameToDeleteTagsWith = substitute(l:sFilenameToDeleteTagsWith, "\\.", "\\\\\\\\.", "g")
   let l:sFilenameToDeleteTagsWith = substitute(l:sFilenameToDeleteTagsWith, "\\/", "\\\\\\\\/", "g")

   let l:sCmd = "sed -e \"/".l:sFilenameToDeleteTagsWith."/d\" -i \"".a:dParams.sTagsFile."\""

   let l:resp = system(l:sCmd)
   "if exists("*AsyncCommand")
      "call AsyncCommand(l:sCmd, "")
   "else
      "let l:resp = system(l:sCmd)
   "endif

endfunction

" ************************************************************************************************
"                                   CTAGS SPECIAL FUNCTIONS
" ************************************************************************************************

function! <SID>UpdateAllTagsForProject(sProjFileKey, sProjName, sSavedFile)

   let l:sTagsFile = s:dProjFilesParsed[ a:sProjFileKey ]["projects"][ a:sProjName ].tagsFilename
   let l:dCurProject = s:dProjFilesParsed[a:sProjFileKey]["projects"][ a:sProjName ]

   if (!empty(a:sSavedFile) && filereadable(l:sTagsFile))
      " just appending tags from just saved file. (from one file!)
      if (g:indexer_useSedWhenAppend)
         call <SID>ExecSed({'sTagsFile': l:sTagsFile, 'sFilenameToDeleteTagsWith': a:sSavedFile})
      endif
      call <SID>ExecCtags({'append': 1, 'recursive': 0, 'sTagsFile': l:sTagsFile, 'sFiles': a:sSavedFile})
   else
      " need to rebuild all tags.

      " deleting old tagsfile
      if (filereadable(l:sTagsFile))
         call delete(l:sTagsFile)
      endif

      " generating tags for files
      call <SID>ExecCtagsForListOfFiles({'lFilelist': l:dCurProject.files,          'sTagsFile': l:sTagsFile,  'recursive': 0})
      " generating tags for directories
      call <SID>ExecCtagsForListOfFiles({'lFilelist': l:dCurProject.pathsForCtags,  'sTagsFile': l:sTagsFile,  'recursive': 1})

   endif




   let s:dProjFilesParsed[ a:sProjFileKey ]["projects"][ a:sProjName ].boolIndexed = 1

endfunction


"function! <SID>UpdateAllTagsForAllProjectsFromFile(sProjFileKey)
   "for l:sCurProjName in keys(s:dProjFilesParsed[ a:sProjFileKey ])
      "call UpdateAllTagsForProject(a:sProjFileKey, l:sCurProjName)
   "endfor
"endfunction








" ************************************************************************************************
"                         FUNCTIONS TO PARSE PROJECT FILE OR INDEXER FILE
" ************************************************************************************************

" возвращает dictionary:
" dResult[<название_проекта_1>][files]
"                              [paths]
"                              [not_exist]
"                              [pathsForCtags]
"                              [pathsRoot]
" dResult[<название_проекта_2>][files]
"                              [paths]
"                              [not_exist]
"                              [pathsForCtags]
"                              [pathsRoot]
" ...
"
" параметры:                             
" param aLines все строки файла (т.е. файл надо сначала прочитать)
" param projectName название проекта, который нужно прочитать.
"                   если пустой, то будут прочитаны
"                   все проекты из файла
" param dExistsResult уже существующий dictionary, к которому будут
" добавлены полученные результаты
"
function! <SID>GetDirsAndFilesFromIndexerList(aLines, projectName, dExistsResult)
   let l:aLines = a:aLines
   let l:dResult = a:dExistsResult
   let l:boolInNeededProject = (a:projectName == '' ? 1 : 0)
   let l:boolInProjectsParentSection = 0
   let l:sProjectsParentFilter = ''

   let l:sCurProjName = ''

   for l:sLine in l:aLines

      " if line is not empty
      if l:sLine !~ '^\s*$' && l:sLine !~ '^\s*\#.*$'

         " look for project name [PrjName]
         let myMatch = matchlist(l:sLine, '^\s*\[\([^\]]\+\)\]')

         if (len(myMatch) > 0)

            " check for PROJECTS_PARENT section

            if (strpart(myMatch[1], 0, 15) == 'PROJECTS_PARENT')
               " this is projects parent section
               let l:sProjectsParentFilter = ''
               let filterMatch = matchlist(myMatch[1], 'filter="\([^"]\+\)"')
               if (len(filterMatch) > 0)
                  let l:sProjectsParentFilter = filterMatch[1]
               endif
               let l:boolInProjectsParentSection = 1
            else
               let l:boolInProjectsParentSection = 0


               if (a:projectName != '')
                  if (myMatch[1] == a:projectName)
                     let l:boolInNeededProject = 1
                  else
                     let l:boolInNeededProject = 0
                  endif
               endif

               if l:boolInNeededProject
                  let l:sCurProjName = myMatch[1]
                  let l:dResult[l:sCurProjName] = { 'files': [], 'paths': [], 'not_exist': [], 'pathsForCtags': [], 'pathsRoot': [] }
               endif
            endif
         else

            if l:boolInProjectsParentSection
               " parsing one project parent

               let l:lFilter = split(l:sProjectsParentFilter, ' ')
               if (len(l:lFilter) == 0)
                  let l:lFilter = ['*']
               endif
               " removing \/* from end of path
               let l:projectsParent = substitute(<SID>Trim(l:sLine), '[\\/*]\+$', '', '')

               " creating list of projects
               let l:lProjects = split(expand(l:projectsParent.'/*'), '\n')
               let l:lIndexerFilesList = []
               for l:sPrj in l:lProjects
                  if (isdirectory(l:sPrj))
                     call add(l:lIndexerFilesList, '['.substitute(l:sPrj, '^.*[\\/]\([^\\/]\+\)$', '\1', '').']')
                     for l:sCurFilter in l:lFilter
                        call add(l:lIndexerFilesList, l:sPrj.'/**/'.l:sCurFilter)
                     endfor
                     call add(l:lIndexerFilesList, '')
                  endif
               endfor
               " parsing this list
               let l:dResult = <SID>GetDirsAndFilesFromIndexerList(l:lIndexerFilesList, a:projectName, l:dResult)
               
            elseif l:boolInNeededProject
               " looks like there's path
               if l:sCurProjName == ''
                  let l:sCurProjName = 'noname'
                  let l:dResult[l:sCurProjName] = { 'files': [], 'paths': [], 'not_exist': [], 'pathsForCtags': [], 'pathsRoot': [] }
               endif

               " we should separately expand every variable
               " like $BLABLABLA
               let l:sPatt = "\\v(\\$[a-zA-Z0-9_]+)"
               while (1)
                  let varMatch = matchlist(l:sLine, l:sPatt)
                  " if there's any $BLABLA in string
                  if (len(varMatch) > 0)
                     " changing one slash in value to doubleslash
                     let l:sTmp = substitute(expand(varMatch[1]), "\\\\", "\\\\\\\\", "g")
                     " changing $BLABLA to its value (doubleslashed)
                     let l:sLine = substitute(l:sLine, l:sPatt, l:sTmp, "")
                  else 
                     break
                  endif
               endwhile

               let l:sTmpLine = l:sLine
               " removing last part of path (removing all after last slash)
               let l:sTmpLine = substitute(l:sTmpLine, '^\(.*\)[\\/][^\\/]\+$', '\1', 'g')
               " removing asterisks at end of line
               let l:sTmpLine = substitute(l:sTmpLine, '^\([^*]\+\).*$', '\1', '')
               " removing final slash
               let l:sTmpLine = substitute(l:sTmpLine, '[\\/]$', '', '')

               let l:dResult[l:sCurProjName].pathsRoot = <SID>ConcatLists(l:dResult[l:sCurProjName].pathsRoot, [<SID>ParsePath(l:sTmpLine)])
               let l:dResult[l:sCurProjName].paths = <SID>ConcatLists(l:dResult[l:sCurProjName].paths, [<SID>ParsePath(l:sTmpLine)])

               " -- now we should generate all subdirs

               " getting string with all subdirs
               let l:sDirs = expand(l:sTmpLine."/**/")
               " removing final slash at end of every dir
               let l:sDirs = substitute(l:sDirs, '\v[\\/](\n|$)', '\1', 'g')
               " getting list from string
               let l:lDirs = split(l:sDirs, '\n')


               let l:dResult[l:sCurProjName].paths = <SID>ConcatLists(l:dResult[l:sCurProjName].paths, l:lDirs)


               if (!s:dVimprjRoots[ s:curVimprjKey ].useDirsInsteadOfFiles)
                  " adding every file.
                  let l:dResult[l:sCurProjName].files = <SID>ConcatLists(l:dResult[l:sCurProjName].files, split(expand(substitute(<SID>Trim(l:sLine), '\\\*\*', '**', 'g')), '\n'))
               else
                  " adding just paths. (much more faster)
                  let l:dResult[l:sCurProjName].pathsForCtags = l:dResult[l:sCurProjName].pathsRoot
               endif
            endif

         endif
      endif

   endfor

   return l:dResult
endfunction

" getting dictionary with files, paths and non-existing files from indexer
" project file
function! <SID>GetDirsAndFilesFromIndexerFile(indexerFile, projectName)
   let l:aLines = readfile(a:indexerFile)
   let l:dResult = {}
   let l:dResult = <SID>GetDirsAndFilesFromIndexerList(l:aLines, a:projectName, l:dResult)
   return l:dResult
endfunction

" getting dictionary with files, paths and non-existing files from
" project.vim's project file
function! <SID>GetDirsAndFilesFromProjectFile(projectFile, projectName)
   let l:aLines = readfile(a:projectFile)
   " if projectName is empty, then we should add files from whole projectFile
   let l:boolInNeededProject = (a:projectName == '' ? 1 : 0)

   let l:iOpenedBraces = 0 " current count of opened { }
   let l:iOpenedBracesAtProjectStart = 0
   let l:aPaths = [] " paths stack
   let l:sLastFoundPath = ''

   let l:dResult = {}
   let l:sCurProjName = ''

   for l:sLine in l:aLines
      " ignoring comments
      if l:sLine =~ '^#' | continue | endif

      let l:sLine = substitute(l:sLine, '#.\+$', '' ,'')
      " searching for closing brace { }
      let sTmpLine = l:sLine
      while (sTmpLine =~ '}')
         let l:iOpenedBraces = l:iOpenedBraces - 1

         " if projectName is defined and there was last brace closed, then we
         " are finished parsing needed project
         if (l:iOpenedBraces <= l:iOpenedBracesAtProjectStart) && a:projectName != ''
            let l:boolInNeededProject = 0
            " TODO: total break
         endif
         call remove(l:aPaths, len(l:aPaths) - 1)

         let sTmpLine = substitute(sTmpLine, '}', '', '')
      endwhile

      " searching for blabla=qweqwe
      let myMatch = matchlist(l:sLine, '\s*\(.\{-}\)=\(.\{-}\)\\\@<!\(\s\|$\)')
      if (len(myMatch) > 0)
         " now we found start of project folder or subfolder
         "
         if !l:boolInNeededProject
            if (a:projectName != '' && myMatch[1] == a:projectName)
               let l:iOpenedBracesAtProjectStart = l:iOpenedBraces
               let l:boolInNeededProject = 1
            endif
         endif

         if l:boolInNeededProject && (l:iOpenedBraces == l:iOpenedBracesAtProjectStart)
            let l:sCurProjName = myMatch[1]
            let l:dResult[myMatch[1]] = { 'files': [], 'paths': [], 'not_exist': [], 'pathsForCtags': [], 'pathsRoot': [] }
         endif

         let l:sLastFoundPath = myMatch[2]
         " ADDED! Jkooij
         " Strip the path of surrounding " characters, if there are any
         let l:sLastFoundPath = substitute(l:sLastFoundPath, "\"\\(.*\\)\"", "\\1", "g")
         let l:sLastFoundPath = expand(l:sLastFoundPath) " Expand any environment variables that might be in the path
         let l:sLastFoundPath = <SID>ParsePath(l:sLastFoundPath)

      endif

      " searching for opening brace { }
      let sTmpLine = l:sLine
      while (sTmpLine =~ '{')

         if (<SID>IsAbsolutePath(l:sLastFoundPath) || len(l:aPaths) == 0)
            call add(l:aPaths, <SID>ParsePath(l:sLastFoundPath))
         else
            call add(l:aPaths, <SID>ParsePath(l:aPaths[len(l:aPaths) - 1].'/'.l:sLastFoundPath))
         endif

         let l:iOpenedBraces = l:iOpenedBraces + 1

         " adding current path to paths list if we are in needed project.
         if (l:boolInNeededProject && l:iOpenedBraces > l:iOpenedBracesAtProjectStart && isdirectory(l:aPaths[len(l:aPaths) - 1]))
            " adding to paths (that are with all subfolders)
            call add(l:dResult[l:sCurProjName].paths, l:aPaths[len(l:aPaths) - 1])
            " if last found path was absolute, then adding it to pathsRoot
            if (<SID>IsAbsolutePath(l:sLastFoundPath))
               call add(l:dResult[l:sCurProjName].pathsRoot, l:aPaths[len(l:aPaths) - 1])
            endif
         endif

         let sTmpLine = substitute(sTmpLine, '{', '', '')
      endwhile

      " searching for filename (if there's files-mode, not dir-mode)
      if (!s:dVimprjRoots[ s:curVimprjKey ].useDirsInsteadOfFiles)
         if (l:sLine =~ '^[^={}]*$' && l:sLine !~ '^\s*$')
            " here we found something like filename
            "
            if (l:boolInNeededProject && l:iOpenedBraces > l:iOpenedBracesAtProjectStart)
               " we are in needed project
               "let l:sCurFilename = expand(<SID>ParsePath(l:aPaths[len(l:aPaths) - 1].'/'.<SID>Trim(l:sLine)))
               " CHANGED! Jkooij
               " expand() will change slashes based on 'shellslash' flag,
               " so call <SID>ParsePath() on expand() result for consistent slashes
               let l:sCurFilename = <SID>ParsePath(expand(l:aPaths[len(l:aPaths) - 1].'/'.<SID>Trim(l:sLine)))
               if (filereadable(l:sCurFilename))
                  " file readable! adding it
                  call add(l:dResult[l:sCurProjName].files, l:sCurFilename)
               elseif (!isdirectory(l:sCurFilename))
                  call add(l:dResult[l:sCurProjName].not_exist, l:sCurFilename)
               endif
            endif

         endif
      endif

   endfor

   " if there's dir-mode then let's set pathsForCtags = pathsRoot
   if (s:dVimprjRoots[ s:curVimprjKey ].useDirsInsteadOfFiles)
      for l:sKey in keys(l:dResult)
         let l:dResult[l:sKey].pathsForCtags = l:dResult[l:sKey].pathsRoot
      endfor
      
   endif

   return l:dResult
endfunction








" ************************************************************************************************
"                                       MAIN FUNCTIONS
" ************************************************************************************************

function! <SID>OnBufSave()
   let l:sSavedFile = <SID>ParsePath(expand('<afile>:p'))
   "let l:sSavedFilePath = <SID>ParsePath(expand('%:p:h'))

   " для каждого проекта, в который входит файл, ...

   for l:lFileProjs in s:dFiles[ s:curFileNum ]["projects"]
      let l:dCurProject = s:dProjFilesParsed[ l:lFileProjs.file ]["projects"][ l:lFileProjs.name ]

      " if saved file is present in non-existing filelist then moving file from non-existing list to existing list
      if (<SID>IsFileExistsInList(l:dCurProject.not_exist, l:sSavedFile))
         call remove(l:dCurProject.not_exist, index(l:dCurProject.not_exist, l:sSavedFile))
         call add(l:dCurProject.files, l:sSavedFile)
      endif

      if g:indexer_ctagsJustAppendTagsAtFileSave
         call <SID>UpdateAllTagsForProject(l:lFileProjs.file, l:lFileProjs.name, l:sSavedFile)
      else
         call <SID>UpdateAllTagsForProject(l:lFileProjs.file, l:lFileProjs.name, "")
      endif

   endfor
endfunction

" updating tags using ctags.
" if boolAppend then just appends existing tags file with new tags from
" current file (%)
"function! <SID>UpdateTags(boolAppend)

   "" one tags file
   
   "let l:sTagsFileWOPath = substitute(join(g:indexer_indexedProjects, '_'), '\s', '_', 'g')
   "let l:sTagsFile = s:tagsDirname.'/'.l:sTagsFileWOPath
   "if !isdirectory(s:tagsDirname)
      "call mkdir(s:tagsDirname, "p")
   "endif

   "" if saved file is present in non-existing filelist then moving file from non-existing list to existing list
   "let l:sSavedFile = <SID>ParsePath(expand('%:p'))
   "let l:sSavedFilePath = <SID>ParsePath(expand('%:p:h'))
   "if (<SID>IsFileExistsInList(s:dParseGlobal.not_exist, l:sSavedFile))
      "call remove(s:dParseGlobal.not_exist, index(s:dParseGlobal.not_exist, l:sSavedFile))
      "call add(s:dParseGlobal.files, l:sSavedFile)
   "endif

   "let l:sRecurseCode = ''


   "if (<SID>IsFileExistsInList(s:dParseGlobal.files, l:sSavedFile) || <SID>IsFileExistsInList(s:dParseGlobal.paths, l:sSavedFilePath))

      "if (a:boolAppend && filereadable(l:sTagsFile))
         "" just appending tags from just saved file. (from one file!)
         "if (g:indexer_useSedWhenAppend)
            "call <SID>ExecSed({'sTagsFile': l:sTagsFile, 'sFilenameToDeleteTagsWith': l:sSavedFile})
         "endif
         "call <SID>ExecCtags({'append': 1, 'recursive': 0, 'sTagsFile': l:sTagsFile, 'sFiles': l:sSavedFile})
      "else
         "" need to rebuild all tags.
         
         "" deleting old tagsfile
         "if (filereadable(l:sTagsFile))
             "call delete(l:sTagsFile)
         "endif

         "" generating tags for files
         "call <SID>ExecCtagsForListOfFiles({'lFilelist': s:dParseGlobal.files,          'sTagsFile': l:sTagsFile,  'recursive': 0})
         "" generating tags for directories
         "call <SID>ExecCtagsForListOfFiles({'lFilelist': s:dParseGlobal.pathsForCtags,  'sTagsFile': l:sTagsFile,  'recursive': 1})

      "endif
   "endif

   "" specifying tags in Vim
   "exec 'set tags+='.substitute(s:tagsDirname.'/'.l:sTagsFileWOPath, ' ', '\\\\\\ ', 'g')
"endfunction

" применяет настройки проекта:
"
" 1) устанавливает пути (&path) из нужных проектов,
" 2) настраивает авто-обновление тегов при сохранении файла проекта
" 3) запускает полное обновление тегов проекта
"
function! <SID>ApplyProjectSettings()
   " paths for Vim
   "set path=.
   for l:sPath in s:dParseGlobal.paths
      if isdirectory(l:sPath)
         exec 'set path+='.substitute(l:sPath, ' ', '\\ ', 'g')
      endif
   endfor

   augroup Indexer_SavSrcFile
      autocmd! Indexer_SavSrcFile BufWritePost
   augroup END

   if (!s:dVimprjRoots[ s:curVimprjKey ].useDirsInsteadOfFiles)
      " If plugin knows every filename, then
      " collect extensions of files in project to make autocmd on save these
      " files
      let l:sExtsList = ''
      let l:lFullList = s:dParseGlobal.files + s:dParseGlobal.not_exist
      for l:lFile in l:lFullList
         let l:sExt = substitute(l:lFile, '^.*\([.\\/][^.\\/]\+\)$', '\1', '')
         if strpart(l:sExt, 0, 1) != '.'
            let l:sExt = strpart(l:sExt, 1)
         endif
         if (stridx(l:sExtsList, l:sExt) == -1)
            if (l:sExtsList != '')
               let l:sExtsList = l:sExtsList.','
            endif
            let l:sExtsList = l:sExtsList.'*'.l:sExt
         endif
      endfor

      " defining autocmd at source files save
      exec 'autocmd Indexer_SavSrcFile BufWritePost '.l:sExtsList.' call <SID>UpdateTags('.(s:dVimprjRoots[ s:curVimprjKey ].ctagsJustAppendTagsAtFileSave ? '1' : '0').')'
   else
      " if plugin knows just directories, then it will update tags at any
      " filesave.
      exec 'autocmd Indexer_SavSrcFile BufWritePost * call <SID>UpdateTags('.(s:dVimprjRoots[ s:curVimprjKey ].ctagsJustAppendTagsAtFileSave ? '1' : '0').')'
   endif

   " start full tags update
   call <SID>UpdateTags(0)
endfunction

"function! <SID>ParseProjectSettingsFile()



   "" теперь мы знаем, какие проекты нужно индексировать.
   "" Сливаем списки файлов и директорий из каждого массива
   "" отдельного проекта в общий массив s:dParseGlobal
   ""
   "" build final list of files, paths and non-existing files
   "let s:dParseGlobal = { 'files':[], 'paths':[], 'not_exist':[], 'pathsForCtags':[], 'pathsRoot':[] }

   "for l:sCurProjName in g:indexer_indexedProjects
      "let s:dParseGlobal.files = <SID>ConcatLists(s:dParseGlobal.files, l:dParseAll[l:sCurProjName].files)
      "let s:dParseGlobal.paths = <SID>ConcatLists(s:dParseGlobal.paths, l:dParseAll[l:sCurProjName].paths)
      "let s:dParseGlobal.pathsForCtags = <SID>ConcatLists(s:dParseGlobal.pathsForCtags, l:dParseAll[l:sCurProjName].pathsForCtags)
      "let s:dParseGlobal.not_exist = <SID>ConcatLists(s:dParseGlobal.not_exist, l:dParseAll[l:sCurProjName].not_exist)
      "let s:dParseGlobal.pathsRoot = <SID>ConcatLists(s:dParseGlobal.pathsRoot, l:dParseAll[l:sCurProjName].pathsRoot)
   "endfor

   "let s:lPathsForCtags = s:dParseGlobal.pathsForCtags
   "let s:lPathsRoot = s:dParseGlobal.pathsRoot

   "if (s:boolIndexingModeOn)
      "call <SID>ApplyProjectSettings()
   "else
      "if (len(s:dParseGlobal.files) > 0 || len(s:dParseGlobal.paths) > 0)

         "let s:boolIndexingModeOn = 1

         "" creating auto-refresh index at project file save
         "augroup Indexer_SavPrjFile
            "autocmd! Indexer_SavPrjFile BufWritePost
         "augroup END

         "if (filereadable(s:dVimprjRoots[ s:curVimprjKey ].indexerListFilename))
            "let l:sIdxFile = substitute(s:dVimprjRoots[ s:curVimprjKey ].indexerListFilename, '^.*[\\/]\([^\\/]\+\)$', '\1', '')
            "exec 'autocmd Indexer_SavPrjFile BufWritePost '.l:sIdxFile.' call <SID>ParseProjectSettingsFile()'
         "elseif (filereadable(s:dVimprjRoots[ s:curVimprjKey ].projectsSettingsFilename))
            "let l:sPrjFile = substitute(s:dVimprjRoots[ s:curVimprjKey ].projectsSettingsFilename, '^.*[\\/]\([^\\/]\+\)$', '\1', '')
            "exec 'autocmd Indexer_SavPrjFile BufWritePost '.l:sPrjFile.' call <SID>ParseProjectSettingsFile()'
         "endif

         "call <SID>ApplyProjectSettings()

         "let l:iNonExistingCnt = len(s:dParseGlobal.not_exist)
         "if (l:iNonExistingCnt > 0)
            "if l:iNonExistingCnt < 100
               "echo "Indexer Warning: project loaded, but there's ".l:iNonExistingCnt." non-existing files: \n\n".join(s:dParseGlobal.not_exist, "\n")
            "else
               "echo "Indexer Warning: project loaded, but there's ".l:iNonExistingCnt." non-existing files. Type :IndexerInfo for details."
            "endif
         "endif
      "else
         "" there's no project started.
         "" we should define autocmd to detect if file from project will be opened later
         "augroup Indexer_LoadFile
            "autocmd! Indexer_LoadFile BufReadPost
            "autocmd Indexer_LoadFile BufReadPost * call <SID>OnNewFileOpened()
         "augroup END
      "endif
   "endif
"endfunction



function! <SID>OnBufEnter()
   if (<SID>NeedSkipBuffer('%'))
      return
   endif

   if (!<SID>IsBufChanged())
       return
   endif

   "let l:sTmp = input("OnBufWinEnter_".getbufvar('%', "&buftype"))

   call <SID>SetCurrentFile()
   let $INDEXER_PROJECT_ROOT = s:dVimprjRoots[ s:curVimprjKey ].proj_root

   let &tags = s:sTagsDefault
   let &path = s:sPathDefault

   "" TODO: сбросить все g:indexer_.. на дефолтные
   "source $MYVIMRC

   "let l:sTmp = &ts
   if (!empty(g:indexer_defaultSettingsFilename))
       exec 'source '.g:indexer_defaultSettingsFilename
   endif
   "echo s:dVimprjRoots
   "let l:sdfsdf = input("sdf")
   "let l:sTmp .= "===".&ts
   "let l:sTmp .= "==curVimprjKey(".s:curVimprjKey.")"
   "let l:sTmp .= "==path(".s:dVimprjRoots[ s:curVimprjKey ]["path"].")"

   if (!empty(s:dVimprjRoots[ s:curVimprjKey ].path))
      " sourcing all *vim files in .vimprj dir
      let l:lSourceFilesList = split(glob(s:dVimprjRoots[ s:curVimprjKey ]["path"].'/*vim'), '\n')
      let l:sThisFile = expand('%:p')
      for l:sFile in l:lSourceFilesList
         exec 'source '.l:sFile
      endfor

   endif

   "let l:sTmp .= "===".&ts
   "let l:tmp2 = input(l:sTmp)
   " для каждого проекта, в который входит файл, добавляем tags и path

   for l:lFileProjs in s:dFiles[ s:curFileNum ]["projects"]
      exec "set tags+=". s:dProjFilesParsed[ l:lFileProjs.file ]["projects"][ l:lFileProjs.name ]["tagsFilenameEscaped"]
      exec "set path+=".s:dProjFilesParsed[ l:lFileProjs.file ]["projects"][ l:lFileProjs.name ]["sPathsAll"]
   endfor

   " переключаем рабочую директорию
   exec "cd ".s:dVimprjRoots[ s:curVimprjKey ]["cd_path"]
endfunction



function! <SID>OnNewFileOpened()
   if (<SID>NeedSkipBuffer('%'))
      return
   endif

   "let l:sTmp = input("OnNewFileOpened_".getbufvar('%', "&buftype"))

   " actual tags dirname. If .vimprj directory will be found then this tags
   " dirname will be /path/to/dir/.vimprj/tags
   let g:indexer_indexedProjects = []
   let s:lPathsForCtags = []

   " ищем .vimprj
   let l:sVimprjKey = "default"
   if g:indexer_lookForProjectDir
      " need to look for .vimprj directory

      let l:i = 0
      let l:sCurPath = ''
      let $INDEXER_PROJECT_ROOT = ''
      while (l:i < g:indexer_recurseUpCount)
         if (isdirectory(expand('%:p:h').l:sCurPath.'/'.g:indexer_dirNameForSearch))
            let $INDEXER_PROJECT_ROOT = simplify(expand('%:p:h').l:sCurPath)
            exec 'cd '.substitute($INDEXER_PROJECT_ROOT, ' ', '\\ ', 'g')
            break
         endif
         let l:sCurPath = l:sCurPath.'/..'
         let l:i = l:i + 1
      endwhile

      if $INDEXER_PROJECT_ROOT != ''
         " project root was found.
         "
         " set directory for tags in .vimprj dir
         " let s:tagsDirname = $INDEXER_PROJECT_ROOT.'/'.g:indexer_dirNameForSearch.'/tags'


         " sourcing all *vim files in .vimprj dir
         let l:lSourceFilesList = split(glob($INDEXER_PROJECT_ROOT.'/'.g:indexer_dirNameForSearch.'/*vim'), '\n')
         let l:sThisFile = expand('%:p')
         for l:sFile in l:lSourceFilesList
            exec 'source '.l:sFile
         endfor

         let l:sVimprjKey = <SID>GetKeyFromPath($INDEXER_PROJECT_ROOT)
         call <SID>AddNewVimprjRoot(l:sVimprjKey, $INDEXER_PROJECT_ROOT, $INDEXER_PROJECT_ROOT)

      endif

   endif

   call <SID>AddCurrentFile(l:sVimprjKey)


   " выясняем, какой файл проекта нужно юзать
   " смотрим: еще не парсили этот файл? (dProjFilesParsed)
   "    парсим
   " endif
   if (filereadable(s:dVimprjRoots[ s:curVimprjKey ].indexerListFilename))
      " read all projects from proj file
      let l:sProjFilename = s:dVimprjRoots[ s:curVimprjKey ].indexerListFilename
      let s:dVimprjRoots[ s:curVimprjKey ].mode = 'IndexerFile'

   elseif (filereadable(s:dVimprjRoots[ s:curVimprjKey ].projectsSettingsFilename))
      " read all projects from indexer file
      let l:sProjFilename = s:dVimprjRoots[ s:curVimprjKey ].projectsSettingsFilename
      let s:dVimprjRoots[ s:curVimprjKey ].mode = 'ProjectFile'

   else
      let l:sProjFilename = ''
      let s:dVimprjRoots[ s:curVimprjKey ].mode = ''
   endif

   let l:sProjFileKey = <SID>GetKeyFromPath(l:sProjFilename)

   if (l:sProjFileKey != "") " если нашли файл с описанием проектов
      if (!exists("s:dProjFilesParsed['".l:sProjFileKey."']"))
         " если этот файл еще не обрабатывали
         let s:dProjFilesParsed[ l:sProjFileKey ] = {"filename" : l:sProjFilename, "projects" : {} }

         if (s:dVimprjRoots[ s:curVimprjKey ].mode == 'IndexerFile')
            let s:dProjFilesParsed[l:sProjFileKey]["projects"] = <SID>GetDirsAndFilesFromIndexerFile(s:dVimprjRoots[ s:curVimprjKey ].indexerListFilename, s:dVimprjRoots[ s:curVimprjKey ].projectName)
         elseif (s:dVimprjRoots[ s:curVimprjKey ].mode == 'ProjectFile')
            let s:dProjFilesParsed[l:sProjFileKey]["projects"] = <SID>GetDirsAndFilesFromProjectFile(s:dVimprjRoots[ s:curVimprjKey ].projectsSettingsFilename, s:dVimprjRoots[ s:curVimprjKey ].projectName)
         endif

         " для каждого проекта из файла с описанием проектов
         " указываем параметры:
         "     boolIndexed = 0
         "     tagsFilename - имя файла тегов
         for l:sCurProjName in keys(s:dProjFilesParsed[ l:sProjFileKey ]["projects"])
            let s:dProjFilesParsed[l:sProjFileKey]["projects"][ l:sCurProjName ]["boolIndexed"] = 0

            "let l:sTagsFileWOPath = <SID>GetKeyFromPath(l:sProjFileKey.'_'.l:sCurProjName)
            "let l:sTagsFile = s:tagsDirname.'/'.l:sTagsFileWOPath

            " если директория для тегов не указана в конфиге - значит, юзаем
            " /path/to/.vimprojects_tags/  (или ....indexer_files)
            " и каждый файл называется так же, как называется проект.
            "
            " а если указана, то все теги кладем в нее, и названия файлов
            " тегов будут длинными, типа: /path/to/tags/D__projects_myproject_vimprj__indexer_files_BK90

            if empty(s:indexer_tagsDirname)
               " директория для тегов НЕ указана
               let l:sTagsDirname = s:dProjFilesParsed[l:sProjFileKey]["filename"]."_tags"
               let l:sTagsFileWOPath = <SID>GetKeyFromPath(l:sCurProjName)
            else
               " директория для тегов указана
               let l:sTagsDirname = s:indexer_tagsDirname
               let l:sTagsFileWOPath = <SID>GetKeyFromPath(l:sProjFileKey.'_'.l:sCurProjName)
            endif

            let l:sTagsFile = l:sTagsDirname.'/'.l:sTagsFileWOPath


            if !isdirectory(l:sTagsDirname)
               call mkdir(l:sTagsDirname, "p")
            endif

            let s:dProjFilesParsed[l:sProjFileKey]["projects"][ l:sCurProjName ]["tagsFilename"] = l:sTagsFile
            let s:dProjFilesParsed[l:sProjFileKey]["projects"][ l:sCurProjName ]["tagsFilenameEscaped"]=substitute(l:sTagsFile, ' ', '\\\\\\ ', 'g')

            let l:sPathsAll = ""
            for l:sPath in s:dProjFilesParsed[l:sProjFileKey]["projects"][l:sCurProjName].paths
               if isdirectory(l:sPath)
                  let l:sPathsAll .= substitute(l:sPath, ' ', '\\ ', 'g').","
                  "exec 'set path+='.substitute(l:sPath, ' ', '\\ ', 'g')
               endif
            endfor
            let s:dProjFilesParsed[l:sProjFileKey]["projects"][ l:sCurProjName ]["sPathsAll"] = l:sPathsAll

         endfor

         " TODO добавляем autocmd BufWritePost для файла с описанием проекта

         if (s:dVimprjRoots[ s:curVimprjKey ].mode == 'IndexerFile')
            let l:sIdxFile = substitute(s:dVimprjRoots[ s:curVimprjKey ].indexerListFilename, '^.*[\\/]\([^\\/]\+\)$', '\1', '')
            "exec 'autocmd Indexer_SavPrjFile BufWritePost '.l:sIdxFile.' call <SID>ParseProjectSettingsFile()'
         elseif (s:dVimprjRoots[ s:curVimprjKey ].mode == 'ProjectFile')
            let l:sPrjFile = substitute(s:dVimprjRoots[ s:curVimprjKey ].projectsSettingsFilename, '^.*[\\/]\([^\\/]\+\)$', '\1', '')
            "exec 'autocmd Indexer_SavPrjFile BufWritePost '.l:sPrjFile.' call <SID>ParseProjectSettingsFile()'
         endif


      endif

      "
      " Если пользователь не указал явно, какой проект он хочет проиндексировать,
      " ( опция g:indexer_projectName )
      " то
      " надо выяснить, какие проекты включать в список проиндексированных.
      " тут два варианта: 
      " 1) мы включаем проект, если открытый файл находится в
      "    любой его поддиректории
      " 2) мы включаем проект, если открытый файл прямо указан 
      "    в списке файлов проекта
      "    
      " есть опция: g:indexer_enableWhenProjectDirFound, она прямо указывает,
      "             нужно ли включать любой файл из поддиректории, или нет.
      "             Но еще есть опция g:indexer_useDirsInsteadOfFiles, и если
      "             она установлена, то плагин вообще не знает ничего про 
      "             конкретные файлы, поэтому мы должны себя вести также, какой
      "             если установлена первая опция.
      "
      " Еще один момент: если включаем проект только если открыт файл именно
      "                  из этого проекта, то просто сравниваем имя файла 
      "                  со списком файлов из проекта.
      "
      "                  А вот если включаем проект, если открыт файл из
      "                  поддиректории, то нужно еще подниматься вверх по дереву,
      "                  т.к. может оказаться, что директория, в которой
      "                  находится открытый файл, является поддиректорией
      "                  проекта, но не перечислена явно в файле проекта.
      "
      "
      if (s:dVimprjRoots[ s:curVimprjKey ].projectName == '')
         " пользователь не указал явно название проекта. Нам нужно выяснять.

         let l:iProjectsAddedCnt = 0
         let l:lProjects = []
         if (s:dVimprjRoots[ s:curVimprjKey ].enableWhenProjectDirFound || s:dVimprjRoots[ s:curVimprjKey ].useDirsInsteadOfFiles)
            " режим директорий
            for l:sCurProjName in keys(s:dProjFilesParsed[ l:sProjFileKey ]["projects"])
               let l:boolFound = 0
               let l:i = 0
               let l:sCurPath = ''
               while (!l:boolFound && l:i < 10)
                  if (<SID>IsFileExistsInList(s:dProjFilesParsed[ l:sProjFileKey ]["projects"][l:sCurProjName].paths, expand('%:p:h').l:sCurPath))
                     " user just opened file from subdir of project l:sCurProjName. 
                     " We should add it to result lists

                     " adding name of this project to g:indexer_indexedProjects
                     "call add(g:indexer_indexedProjects, l:sCurProjName)
                     if l:iProjectsAddedCnt == 0
                         call <SID>AddNewProjectToCurFile(l:sProjFileKey, l:sCurProjName)
                     endif
                     let l:iProjectsAddedCnt = l:iProjectsAddedCnt + 1
                     call add(l:lProjects, l:sCurProjName)
                     break
                  endif
                  let l:i = l:i + 1
                  let l:sCurPath = l:sCurPath.'/..'
               endwhile
            endfor

            if (l:iProjectsAddedCnt > 1)
                echoerr "Warning: directory '".simplify(expand('%:p:h'))."' exists in several projects: '".join(l:lProjects, ', ')."'. Only first is indexed."
                let l:tmp = input(" ")
            endif


         else
            " режим файлов
            for l:sCurProjName in keys(s:dProjFilesParsed[ l:sProjFileKey ]["projects"])
               if (<SID>IsFileExistsInList(s:dProjFilesParsed[ l:sProjFileKey ]["projects"][l:sCurProjName].files, expand('%:p')))
                  " user just opened file from project l:sCurProjName. We should add it to
                  " result lists

                  " adding name of this project to g:indexer_indexedProjects
                  "call add(g:indexer_indexedProjects, l:sCurProjName)
                  if l:iProjectsAddedCnt == 0
                      call <SID>AddNewProjectToCurFile(l:sProjFileKey, l:sCurProjName)
                  endif
                  let l:iProjectsAddedCnt = l:iProjectsAddedCnt + 1
                  call add(l:lProjects, l:sCurProjName)

               endif
            endfor

            if (l:iProjectsAddedCnt > 1)
                echoerr "Warning: file '".simplify(expand('%:t'))."' exists in several projects: '".join(l:lProjects, ', ')."'. Only first is indexed."
                let l:tmp = input(" ")
            endif

         endif

      else    " if projectName != ""
         " пользователь явно указал проект, который нужно проиндексировать
         for l:sCurProjName in keys(s:dProjFilesParsed[ l:sProjFileKey ]["projects"])
            if (l:sCurProjName == s:dVimprjRoots[ s:curVimprjKey ].projectName)
               call <SID>AddNewProjectToCurFile(l:sProjFileKey, l:sCurProjName)
            endif
         endfor

      endif 


      " теперь запускаем ctags для каждого непроиндексированного проекта, 
      " в который входит файл
      for l:sCurProj in s:dFiles[ s:curFileNum ].projects
         if (!s:dProjFilesParsed[ l:sCurProj.file ]["projects"][ l:sCurProj.name ].boolIndexed)
            " генерим теги
            call <SID>UpdateAllTagsForProject(l:sCurProj.file, l:sCurProj.name, "")
         endif

      endfor



   endif " if l:sProjFileKey != ""


   " для того, чтобы при входе в OnBufEnter сработал IsBufChanged, ставим
   " текущий номер буфера в 0
   let s:curFileNum = 0


   "call <SID>ParseProjectSettingsFile()

endfunction



























" ************************************************************************************************
"                                             INIT
" ************************************************************************************************

" --------- init variables --------
if !exists('g:indexer_lookForProjectDir')
   let g:indexer_lookForProjectDir = 1
endif

if !exists('g:indexer_dirNameForSearch')
   let g:indexer_dirNameForSearch = '.vimprj'
endif

if !exists('g:indexer_recurseUpCount')
   let g:indexer_recurseUpCount = 10
endif

if !exists('g:indexer_tagsDirname')
   let g:indexer_tagsDirname = ''  "$HOME.'/.vimtags'
endif

if !exists('g:indexer_maxOSCommandLen')
   if (has('win32') || has('win64'))
      let g:indexer_maxOSCommandLen = 8000
   else
      let g:indexer_maxOSCommandLen = system("echo $(( $(getconf ARG_MAX) - $(env | wc -c) ))") - 200
   endif
endif

if !exists('g:indexer_useSedWhenAppend')
   let g:indexer_useSedWhenAppend = 1
endif






if !exists('g:indexer_indexerListFilename')
   let g:indexer_indexerListFilename = $HOME.'/.indexer_files'
endif


if !exists('g:indexer_projectsSettingsFilename')
   let g:indexer_projectsSettingsFilename = $HOME.'/.vimprojects'
endif

if !exists('g:indexer_projectName')
   let g:indexer_projectName = ''
endif

if !exists('g:indexer_enableWhenProjectDirFound')
   let g:indexer_enableWhenProjectDirFound = '1'
endif

if !exists('g:indexer_ctagsCommandLineOptions')
   let g:indexer_ctagsCommandLineOptions = '--c++-kinds=+p+l --fields=+iaS --extra=+q'
endif

if !exists('g:indexer_ctagsJustAppendTagsAtFileSave')
   let g:indexer_ctagsJustAppendTagsAtFileSave = 1
endif

if !exists('g:indexer_ctagsDontSpecifyFilesIfPossible')
   let g:indexer_ctagsDontSpecifyFilesIfPossible = '0'
endif

if !exists('g:indexer_defaultSettingsFilename')
    let g:indexer_defaultSettingsFilename = ''
endif

let g:indexer_useDirsInsteadOfFiles = g:indexer_ctagsDontSpecifyFilesIfPossible


" -------- init commands ---------

if exists(':IndexerInfo') != 2
   command -nargs=? -complete=file IndexerInfo call <SID>IndexerInfo()
endif
if exists(':IndexerFiles') != 2
   command -nargs=? -complete=file IndexerFiles call <SID>IndexerFilesList()
endif
if exists(':IndexerRebuild') != 2
   command -nargs=? -complete=file IndexerRebuild call <SID>UpdateTags(0)
endif




" запоминаем начальные &tags, &path
let s:sTagsDefault = &tags
let s:sPathDefault = &path

" задаем пустые массивы с данными
let s:dVimprjRoots = {}
let s:dProjFilesParsed = {}
let s:dFiles = {}
let s:curFileNum = 0

" создаем дефолтный "проект"
call <SID>AddNewVimprjRoot("default", "", getcwd())
let s:dFiles[ 0 ] = {'sVimprjKey' : 'default', 'projects': []}

" указываем обработчик открытия нового файла: OnNewFileOpened
augroup Indexer_LoadFile
   autocmd! Indexer_LoadFile BufReadPost
   autocmd Indexer_LoadFile BufReadPost * call <SID>OnNewFileOpened()
   autocmd Indexer_LoadFile BufNewFile * call <SID>OnNewFileOpened()
augroup END

" указываем обработчик входа в другой буфер: OnBufEnter
autocmd BufEnter * call <SID>OnBufEnter()

autocmd BufWritePost * call <SID>OnBufSave()

" запоминаем tagsDirname
let s:indexer_tagsDirname = g:indexer_tagsDirname

" TODO: удалить
let s:boolIndexingModeOn = 0



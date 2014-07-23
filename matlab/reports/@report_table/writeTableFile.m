function o = writeTableFile(o, pg, sec, row, col)
%function o = writeTableFile(o, pg, sec, row, col)
% Write a Report_Table object
%
% INPUTS
%   o   [report_table]    report_table object
%   pg  [integer] this page number
%   sec [integer] this section number
%   row [integer] this row number
%   col [integer] this col number
%
% OUTPUTS
%   o   [report_table]    report_table object
%
% SPECIAL REQUIREMENTS
%   none

% Copyright (C) 2013-2014 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.

ne = length(o.series);
if ne == 0
    warning('@report_table.write: no series to plot, returning');
    return;
end

if isempty(o.tableName)
    o.tableName = sprintf('%s/table_pg%d_sec%d_row%d_col%d.tex', o.tableDirName, pg, sec, row, col);
end

[fid, msg] = fopen(o.tableName, 'w');
if fid == -1
    error(['@report_table.writeTableFile: ' msg]);
end

%number of left-hand columns, 1 until we allow the user to group data,
% e.g.: GDP Europe
%         GDP France
%         GDP Germany
% this example would be two lh columns, with GDP Europe spanning both
nlhc = 1;
if isempty(o.range)
    dates = getMaxRange(o.series);
    o.range = {dates};
else
    dates = o.range{1};
end
ndates = dates.ndat;
datedata = dates.time;
years = unique(datedata(:, 1));
switch dates.freq
    case 1
        sep = 'Y';
    case 4
        sep = 'Q';
    case 12
        sep = 'M';
    case 52
        sep = 'W';
    otherwise
        error('@report_table.writeTableFile: Invalid frequency.');
end

fprintf(fid, '%% Report_Table Object\n');
fprintf(fid, '\\setlength{\\parindent}{6pt}\n');
fprintf(fid, '\\setlength{\\tabcolsep}{4pt}\n');
fprintf(fid, ['\\pgfplotstabletypeset[\n' ...
              '     fixed,\n' ...
              '     fixed zerofill,\n' ...
              '     precision=%d,\n' ...
              '     every head row/.style={\n' ...
              '          before row={\n' ...
              '         \\hline\n' ...
              '         \\rowcolor{%s}\n'], o.precision, o.headerRowColor);
if dates.freq ~= 1
    fprintf(fid, '         \\multicolumn{1}{>{\\columncolor{white}}c}{} &');
    fprintf(fid, '\\multicolumn{%d}{>{\\columncolor{white}}c}{%d} &', ...
            max(dates.freq, dates(end).time(2))-dates(1).time(2)+1, years(1));
    for i=2:length(years)-1
        fprintf(fid, '\\multicolumn{%d}{>{\\columncolor{%s}}c}{%d} &', ...
                dates.freq, o.headerRowColor, years(i));
    end
    if length(years) > 1
        fprintf(fid, '\\multicolumn{%d}{>{\\columncolor{white}}c}{%d}\\\\\n', ...
                dates(end).time(2), years(end));
    end
end
fprintf(fid, ['         \\rowcolor{%s}\n' ...
              '         },\n' ...
              '         after row=\\hline,\n' ...
              '     },\n'], o.headerRowColor);
if o.highlightRows
    fprintf(fid, ['     every even row/.style={\n' ...
                  '         before row={\\rowcolor[gray]{0.9}},\n', ...
                  '         after row={\\rowcolor{white}}},\n']);
end
fprintf(fid, ['     every last row/.style={\n' ...
              '         after row=\\hline\n' ...
              '     },\n']);
fprintf(fid, '     columns/series/.style={column type=l|,column name={},string type},\n');


for i=1:ndates
    fprintf(fid, '     columns/y%d', dates(i).time(1));
    if dates.freq ~= 1
        fprintf(fid, '%s%d', sep, dates(i).time(2));
    end
    fprintf(fid, '/.style={column type=r');
    if o.showVlines
        fprintf(fid, '|');
    else
        if o.vlineAfterEndOfPeriod && dates(i).time(2) == dates.freq
            fprintf(fid, '|');
        end
    end
    if dates.freq == 1
        fprintf(fid, ',column name=$%d$,string type},\n', dates(i).time(1));
    else
        fprintf(fid, ',column name=$%s%d$,string type},\n', sep, dates(i).time(2));
    end
end
fprintf(fid, ']\n{\n');

% Write headers
fprintf(fid, 'series');
for i=1:ndates
    fprintf(fid, ' y%d', dates(i).time(1));
    if dates.freq ~= 1
        fprintf(fid, '%s%d ', sep, dates(i).time(2));
    end
end
fprintf(fid, '\n');

% Write Report_Table Data
for i=1:ne
    o.series{i}.writeSeriesForTable(fid, o.range, o.precision);
    if o.showHlines
        fprintf(fid, '\\hline\n');
    end
end


fprintf(fid, '}\n');
fprintf(fid, '%% End Report_Table Object\n');
if fclose(fid) == -1
    error('@report_table.writeTableFile: closing %s\n', o.filename);
end
return



for i=1:ndates
    if o.showVlines
        fprintf(fid, 'r|');
    else
        fprintf(fid, 'r');
        if o.vlineAfterEndOfPeriod
            if o.range(i).time(2) == o.range(i).freq
                fprintf(fid, '|');
            end
        end
        if ~isempty(o.vlineAfter)
            for j=1:length(o.vlineAfter)
                if o.range(i) == o.vlineAfter{j}
                    if ~(o.vlineAfterEndOfPeriod && o.range(i).time(2) == o.range(i).freq)
                        fprintf(fid, '|');
                    end
                end
            end
        end
    end
end

if length(o.range) > 1
    rhscols = strings(o.range{2});
    if o.range{2}.freq == 1
        rhscols = strrep(rhscols, 'Y', '');
    end
else
    rhscols = {};
end
for i=1:length(rhscols)
    fprintf(fid, 'r');
    if o.showVlines
        fprintf(fid, '|');
    end
end
nrhc = length(rhscols);
ncols = ndates+nlhc+nrhc;
fprintf(fid, '@{}}%%\n');
for i=1:length(o.title)
    if ~isempty(o.title{i})
        fprintf(fid, '\\multicolumn{%d}{c}{%s %s}\\\\\n', ...
                ncols, o.titleFormat{i}, o.title{i});
    end
end
fprintf(fid, '\\toprule%%\n');

% Column Headers
thdr = num2cell(years, size(years, 1));
if o.range.freq == 1
    for i=1:size(thdr, 1)
        fprintf(fid, ' & %d', thdr{i, 1});
    end
    for i=1:length(rhscols)
        fprintf(fid, ' & %s', rhscols{i});
    end
else
    thdr{1, 2} = datedata(:, 2)';
    if size(thdr, 1) > 1
        for i=2:size(thdr, 1)
            split = find(thdr{i-1, 2} == o.range.freq, 1, 'first');
            assert(~isempty(split), '@report_table.writeTableFile: Shouldn''t arrive here');
            thdr{i, 2} = thdr{i-1, 2}(split+1:end);
            thdr{i-1, 2} = thdr{i-1, 2}(1:split);
        end
    end
    for i=1:size(thdr, 1)
        fprintf(fid, ' & \\multicolumn{%d}{c}{%d}', size(thdr{i,2}, 2), thdr{i,1});
    end
    for i=1:length(rhscols)
        fprintf(fid, ' & %s', rhscols{i});
    end
    fprintf(fid, '\\\\\\cline{%d-%d}%%\n', nlhc+1, ncols);
    switch o.range.freq
        case 4
            sep = 'Q';
        case 12
            sep = 'M';
        case 52
            sep = 'W';
        otherwise
            error('@report_table.writeTableFile: Invalid frequency.');
    end
    for i=1:size(thdr, 1)
        period = thdr{i, 2};
        for j=1:size(period, 2)
            fprintf(fid, ' & \\multicolumn{1}{c}{%s%d}', sep, period(j));
        end
    end
end
fprintf(fid, '\\\\[-2pt]%%\n');
fprintf(fid, '\\hline%%\n');
fprintf(fid, '%%\n');

% Write Report_Table Data
for i=1:ne
    o.series{i}.writeSeriesForTable(fid, o.range, o.precision);
    if o.showHlines
        fprintf(fid, '\\hline\n');
    end
end

fprintf(fid, '\\bottomrule\n');
fprintf(fid, '\\end{tabular}\\setlength{\\parindent}{0pt}\n \\par \\medskip\n\n');
fprintf(fid, '%% End Report_Table Object\n');
if fclose(fid) == -1
    error('@report_table.writeTableFile: closing %s\n', o.filename);
end
end

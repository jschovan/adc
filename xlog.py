"""
    based on: https://gist.github.com/leandrosilva/3651640#file-xlog-py
    and adapted.

"""
from pyparsing import Word, alphas, Suppress, Combine, nums, string, Optional, Regex
from time import strftime
import json
import sys

class Parser(object):
    def __init__(self, logfile='./sample.log', resultsfile='./results.json', suffix=""):
        """
            test data:
2015-08-12 03:12:53,127 (UTC) [ DEBUG ] main.batchsubmitplugin[ANALY_SCINET-3755] CondorBaseBatchSubmitPlugin.py:97 submit(): Preparing to submit 5 jobs

        """
        self.logfile = logfile
        self.data = []
        self.results = {}
        self.resultsfile = resultsfile
        self.suffix = suffix
        
        ints = Word(nums)

        # priority
        priority = Suppress("[ ") + Word(alphas + " ") + Suppress("]")

        # timestamp
        year = ints
        month = ints
        day   = ints
        date_combined = Combine(year + "-" + month + "-" + day)
        hour = Combine(ints + ":" + ints + ":" + ints + "," + ints)
        t_zone = Suppress("(") + Word(alphas) + Suppress(")")
        timestamp = date_combined + hour + t_zone

        # label
        label = Word(alphas + nums + "-" + "_" + "." + "[" + "]")

        # plugin
        plugin = Combine(Word(alphas + ".") + label)

        # appname
        appname = Word(alphas + "/" + "-" + "_" + "." + ":" + nums)

        # method
        method = Word(alphas + "-" + "_" + "." + "(" + ")") + Suppress(":")

        # message
        message = Regex(".*")
    
        # pattern build
        self.__pattern = timestamp + priority + plugin + appname + method + message


    def parse(self, line):
        parsed = self.__pattern.parseString(line)

#        print 'parsed:', parsed

        payload = {}
        payload["timestamp"] = ' '.join(parsed[0:3])
        payload["priority"] = parsed[3][:-1]
        payload["plugin"] = parsed[4].split('[')[0]
        payload["label"] = parsed[4].split('[')[1][:-1]
        payload["appname"] = parsed[5]
        payload["method"] = parsed[6]
        payload["message"] = parsed[7]
        payload["njobs"] = parsed[7].split(' ')[3]

        return payload


    def parse_log(self):
        with open(self.logfile) as syslogFile:
            for line in syslogFile:
                fields = self.parse(line)
                self.data.append(fields)
#                print "parsed:", fields
        


    def prepare_results(self):
        nlabels = len(list(set([x['label'] for x in self.data])))
        npilots = sum([int(x['njobs']) for x in self.data \
                       if x['njobs'] is not None])
        self.results['nlabels'] = nlabels
        self.results['npilotwrappers'] = npilots


    def print_results(self):
#        f = open(self.resultsfile, 'w')
#        f.write(json.dumps(self.results, sort_keys=True))
#        f.close()
        res = """<numericvalue desc="Number of submitted pilot wrappers, %(suffix)s" name="npilotwrappers_%(suffix)s">%(npilotwrappers)d</numericvalue><numericvalue desc="Number of served labels, %(suffix)s" name="nlabels_%(suffix)s">%(nlabels)d</numericvalue>""" \
        % {'npilotwrappers': self.results['npilotwrappers'], \
           'nlabels': self.results['nlabels'], \
           'suffix': self.suffix}
        print res


    def run(self):
        self.parse_log()
        self.prepare_results()
        self.print_results()


def main():
    args = sys.argv[1:]
    if len(args) == 3:
        logfile = args[0]
        resultsfile = args[1]
        suffix = args[2]
    else:
        logfile = './sample.log'
        resultsfile = './results.json'
        suffix = ""

    parser = Parser(logfile, resultsfile, suffix)
    parser.run()


if __name__ == "__main__":
    main()
